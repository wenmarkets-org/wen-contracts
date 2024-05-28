// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { WenToken } from "./WenToken.sol";
import { WenHeadmaster } from "./WenHeadmaster.sol";
import { WenLedger } from "./WenLedger.sol";

error InsufficientOutput();
error InsufficientTokenReserve();
error InsufficientEthReserve();
error InsufficientMcap();
error TooMuchMcap();
error AlreadyGraduated();
error DeadlineExceeded();
error InvalidAmountIn();
error Forbidden();
error FeeTooHigh();
error Paused();

/// @title The Wen protocol singleton AMM with a custom bonding curve built-in.
/// @author strobie <@0xstrobe>
/// @notice Owner can pause trading, set fees, and set the graduation strategy, but cannot withdraw funds or modify the bonding curve.
contract WenFoundry is ReentrancyGuard {
    using FixedPointMathLib for uint256;

    struct Pool {
        WenToken token;
        uint256 tokenReserve;
        uint256 virtualTokenReserve;
        uint256 ethReserve;
        uint256 virtualEthReserve;
        uint256 lastPrice;
        uint256 lastMcapInEth;
        uint256 lastTimestamp;
        uint256 lastBlock;
        address creator;
        address headmaster;
        // poolId is not limited to address to support non-uniswap styled AMMs
        uint256 poolId;
    }

    uint8 public constant DECIMALS = 18;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public feeRate_ = 100; // 1%

    uint256 public constant INIT_VIRTUAL_TOKEN_RESERVE = 1073000000 ether;
    uint256 public constant INIT_REAL_TOKEN_RESERVE = 793100000 ether;
    uint256 public constant TOTAL_SUPPLY = 1000000000 ether;
    uint256 public initVirtualEthReserve_;
    uint256 public graduationThreshold_;
    uint256 public K_;

    mapping(WenToken => Pool) public pools_;
    WenLedger public immutable wenLedger_;

    uint256 public creationFee_ = 0;
    uint256 public graduationFeeRate_ = 700;
    address public feeTo_;
    bool public paused_;
    WenHeadmaster public headmaster_; // the contract which implements the graduation logic

    /*//////////////////////////////////////////////////
    /////////////   PERMISSIONED METHODS   /////////////
    //////////////////////////////////////////////////*/

    address public owner_;

    modifier onlyOwner() {
        if (msg.sender != owner_) revert Forbidden();
        _;
    }

    function setFeeTo(address feeTo) external onlyOwner {
        feeTo_ = feeTo;
    }

    function setFeeRate(uint256 feeRate) external onlyOwner {
        if (feeRate > MAX_FEE) revert FeeTooHigh();
        feeRate_ = feeRate;
    }

    function setGraduationFeeRate(uint256 feeRate) external onlyOwner {
        if (feeRate > MAX_FEE) revert FeeTooHigh();
        graduationFeeRate_ = feeRate;
    }

    function setInitVirtualEthReserve(uint256 initVirtualEthReserve) external onlyOwner {
        initVirtualEthReserve_ = initVirtualEthReserve;
        K_ = initVirtualEthReserve_ * INIT_VIRTUAL_TOKEN_RESERVE;
        graduationThreshold_ = K_ / (INIT_VIRTUAL_TOKEN_RESERVE - INIT_REAL_TOKEN_RESERVE) - initVirtualEthReserve_;
    }

    function setCreationFee(uint256 fee) external onlyOwner {
        creationFee_ = fee;
    }

    function setHeadmaster(WenHeadmaster headmaster) external onlyOwner {
        headmaster_ = headmaster;
    }

    function setOwner(address owner) external onlyOwner {
        owner_ = owner;
    }

    function setPaused(bool paused) external onlyOwner {
        paused_ = paused;
    }

    /*//////////////////////////////////////////////////
    ////////////////   CONSTRUCTOR   ///////////////////
    //////////////////////////////////////////////////*/

    constructor(uint256 initVirtualEthReserve) {
        feeTo_ = msg.sender;
        owner_ = msg.sender;
        paused_ = false;

        wenLedger_ = new WenLedger();
        initVirtualEthReserve_ = initVirtualEthReserve;
        K_ = initVirtualEthReserve_ * INIT_VIRTUAL_TOKEN_RESERVE;
        graduationThreshold_ = K_ / (INIT_VIRTUAL_TOKEN_RESERVE - INIT_REAL_TOKEN_RESERVE) - initVirtualEthReserve_;
    }

    /*//////////////////////////////////////////////////
    //////////////////   ASSERTIONS   //////////////////
    //////////////////////////////////////////////////*/

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExceeded();
        _;
    }

    modifier onlyUnpaused() {
        if (paused_) revert Paused();
        _;
    }

    modifier onlyUngraduated(WenToken token) {
        if (pools_[token].headmaster != address(0)) revert AlreadyGraduated();
        if (pools_[token].ethReserve > graduationThreshold_) revert TooMuchMcap();
        _;
    }

    function _isMcapGraduable(WenToken token) private view returns (bool) {
        return pools_[token].ethReserve >= graduationThreshold_;
    }

    /*//////////////////////////////////////////////////
    ////////////////////   EVENTS   ////////////////////
    //////////////////////////////////////////////////*/

    event TokenCreated(WenToken indexed token, address indexed creator);
    event TokenGraduated(WenToken indexed token, WenHeadmaster indexed headmaster, uint256 indexed poolId, uint256 amountToken, uint256 amountETH);
    event Buy(WenToken indexed token, address indexed sender, uint256 amountIn, uint256 amountOut, address indexed to);
    event Sell(WenToken indexed token, address indexed sender, uint256 amountIn, uint256 amountOut, address indexed to);
    event PriceUpdate(WenToken indexed token, address indexed sender, uint256 price, uint256 mcapInEth);

    /*//////////////////////////////////////////////////
    ////////////////   POOL FUNCTIONS   ////////////////
    //////////////////////////////////////////////////*/

    /// @notice Creates a new token in the WenFoundry.
    /// @param name The name of the token.
    /// @param symbol The symbol of the token.
    /// @param initAmountIn The initial amount of ETH to swap for the token.
    /// @param description The description of the token.
    /// @param extended The extended description of the token, typically a JSON string.
    /// @return token The newly created token.
    /// @return amountOut The output amount of token the creator received.
    function createToken(string memory name, string memory symbol, uint256 initAmountIn, string memory description, string memory extended)
        external
        payable
        onlyUnpaused
        returns (WenToken token, uint256 amountOut)
    {
        if (msg.value != initAmountIn + creationFee_) revert InvalidAmountIn();
        if (creationFee_ > 0) {
            SafeTransferLib.safeTransferETH(feeTo_, creationFee_);
        }

        token = _deployToken(name, symbol, description, extended);
        if (initAmountIn > 0) {
            amountOut = _swapEthForTokens(token, initAmountIn, 0, msg.sender);
        }
    }

    function _deployToken(string memory name, string memory symbol, string memory description, string memory extended) private returns (WenToken) {
        WenToken token = new WenToken(name, symbol, DECIMALS, TOTAL_SUPPLY, description, extended, address(this), msg.sender);

        Pool storage pool = pools_[token];
        pool.token = token;
        pool.tokenReserve = INIT_REAL_TOKEN_RESERVE;
        pool.virtualTokenReserve = INIT_VIRTUAL_TOKEN_RESERVE;
        pool.ethReserve = 0;
        pool.virtualEthReserve = initVirtualEthReserve_;
        pool.lastPrice = initVirtualEthReserve_.divWadDown(INIT_VIRTUAL_TOKEN_RESERVE);
        pool.lastMcapInEth = TOTAL_SUPPLY.mulWadUp(pool.lastPrice);
        pool.lastTimestamp = block.timestamp;
        pool.lastBlock = block.number;
        pool.creator = msg.sender;

        emit TokenCreated(token, msg.sender);
        emit PriceUpdate(token, msg.sender, pool.lastPrice, pool.lastMcapInEth);
        wenLedger_.addCreation(token, msg.sender);

        return token;
    }

    function _graduate(WenToken token) private {
        pools_[token].lastTimestamp = block.timestamp;
        pools_[token].lastBlock = block.number;

        uint256 fee = pools_[token].ethReserve * graduationFeeRate_ / FEE_DENOMINATOR;
        SafeTransferLib.safeTransferETH(feeTo_, fee);
        uint256 _amountETH = pools_[token].ethReserve - fee;
        uint256 _amountToken = TOTAL_SUPPLY - INIT_REAL_TOKEN_RESERVE;

        WenToken(address(token)).setIsApprovable(true);
        token.approve(address(headmaster_), type(uint256).max);
        (uint256 poolId, uint256 amountToken, uint256 amountETH) = headmaster_.execute{ value: _amountETH }(token, _amountToken, _amountETH);

        pools_[token].headmaster = address(headmaster_);
        pools_[token].poolId = poolId;
        pools_[token].virtualTokenReserve = 0;
        pools_[token].virtualEthReserve = 0;
        pools_[token].tokenReserve = 0;
        pools_[token].ethReserve = 0;

        emit TokenGraduated(token, headmaster_, poolId, amountToken, amountETH);
        wenLedger_.addGraduation(token, amountETH);
    }

    /*//////////////////////////////////////////////////
    ////////////////   SWAP FUNCTIONS   ////////////////
    //////////////////////////////////////////////////*/

    /// @notice Swaps ETH for tokens.
    /// @param token The token to swap.
    /// @param amountIn Input amount of ETH.
    /// @param amountOutMin Minimum output amount of token.
    /// @param to Recipient of token.
    /// @param deadline Deadline for the swap.
    /// @return amountOut The actual output amount of token.
    function swapEthForTokens(WenToken token, uint256 amountIn, uint256 amountOutMin, address to, uint256 deadline)
        external
        payable
        nonReentrant
        onlyUnpaused
        onlyUngraduated(token)
        checkDeadline(deadline)
        returns (uint256 amountOut)
    {
        if (msg.value != amountIn) revert InvalidAmountIn();

        amountOut = _swapEthForTokens(token, amountIn, amountOutMin, to);

        if (_isMcapGraduable(token)) {
            _graduate(token);
        }
    }

    function _swapEthForTokens(WenToken token, uint256 amountIn, uint256 amountOutMin, address to) private returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmountIn();

        uint256 fee = amountIn * feeRate_ / FEE_DENOMINATOR;
        SafeTransferLib.safeTransferETH(feeTo_, fee);
        amountIn -= fee;

        uint256 newVirtualEthReserve = pools_[token].virtualEthReserve + amountIn;
        uint256 newVirtualTokenReserve = K_ / newVirtualEthReserve;
        amountOut = pools_[token].virtualTokenReserve - newVirtualTokenReserve;

        if (amountOut > pools_[token].tokenReserve) {
            amountOut = pools_[token].tokenReserve;
        }
        if (amountOut < amountOutMin) revert InsufficientOutput();

        pools_[token].virtualTokenReserve = newVirtualTokenReserve;
        pools_[token].virtualEthReserve = newVirtualEthReserve;

        pools_[token].lastPrice = newVirtualEthReserve.divWadDown(newVirtualTokenReserve);
        pools_[token].lastMcapInEth = TOTAL_SUPPLY.mulWadUp(pools_[token].lastPrice);
        pools_[token].lastTimestamp = block.timestamp;
        pools_[token].lastBlock = block.number;

        pools_[token].ethReserve += amountIn;
        pools_[token].tokenReserve -= amountOut;

        SafeTransferLib.safeTransfer(token, to, amountOut);

        emit Buy(token, msg.sender, amountIn + fee, amountOut, to);
        emit PriceUpdate(token, msg.sender, pools_[token].lastPrice, pools_[token].lastMcapInEth);
        WenLedger.Trade memory trade = WenLedger.Trade(token, msg.sender, amountIn + fee, amountOut, true, uint128(block.timestamp), uint128(block.number));
        wenLedger_.addTrade(trade);
    }

    /// @notice Swaps tokens for ETH.
    /// @param token The token to swap.
    /// @param amountIn Input amount of token.
    /// @param amountOutMin Minimum output amount of ETH.
    /// @param to Recipient of ETH.
    /// @param deadline Deadline for the swap.
    /// @return amountOut The actual output amount of ETH.
    function swapTokensForEth(WenToken token, uint256 amountIn, uint256 amountOutMin, address to, uint256 deadline)
        external
        nonReentrant
        onlyUnpaused
        onlyUngraduated(token)
        checkDeadline(deadline)
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InvalidAmountIn();

        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amountIn);

        uint256 newVirtualTokenReserve = pools_[token].virtualTokenReserve + amountIn;
        uint256 newVirtualEthReserve = K_ / newVirtualTokenReserve;
        amountOut = pools_[token].virtualEthReserve - newVirtualEthReserve;

        pools_[token].virtualTokenReserve = newVirtualTokenReserve;
        pools_[token].virtualEthReserve = newVirtualEthReserve;

        pools_[token].lastPrice = newVirtualEthReserve.divWadDown(newVirtualTokenReserve);
        pools_[token].lastMcapInEth = TOTAL_SUPPLY.mulWadUp(pools_[token].lastPrice);
        pools_[token].lastTimestamp = block.timestamp;
        pools_[token].lastBlock = block.number;

        pools_[token].tokenReserve += amountIn;
        pools_[token].ethReserve -= amountOut;

        uint256 fee = amountOut * feeRate_ / FEE_DENOMINATOR;
        amountOut -= fee;

        if (amountOut < amountOutMin) revert InsufficientOutput();
        SafeTransferLib.safeTransferETH(feeTo_, fee);
        SafeTransferLib.safeTransferETH(to, amountOut);

        emit Sell(token, msg.sender, amountIn, amountOut, to);
        emit PriceUpdate(token, msg.sender, pools_[token].lastPrice, pools_[token].lastMcapInEth);
        WenLedger.Trade memory trade = WenLedger.Trade(token, msg.sender, amountIn, amountOut + fee, false, uint128(block.timestamp), uint128(block.number));
        wenLedger_.addTrade(trade);
    }

    /*//////////////////////////////////////////////////
    ////////////////   VIEW FUNCTIONS   ////////////////
    //////////////////////////////////////////////////*/

    /// @notice Calculates the expected output amount of ETH given an input amount of token.
    /// @param token The token to swap.
    /// @param amountIn Input amount of token.
    /// @return amountOut The expected output amount of ETH.
    function calcAmountOutFromToken(WenToken token, uint256 amountIn) external view returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmountIn();

        uint256 newVirtualTokenReserve = pools_[token].virtualTokenReserve + amountIn;
        uint256 newVirtualEthReserve = K_ / newVirtualTokenReserve;
        amountOut = pools_[token].virtualEthReserve - newVirtualEthReserve;

        uint256 fee = amountOut * feeRate_ / FEE_DENOMINATOR;
        amountOut -= fee;
    }

    /// @notice Calculates the expected output amount of token given an input amount of ETH.
    /// @param token The token to swap.
    /// @param amountIn Input amount of ETH.
    /// @return amountOut The expected output amount of token.
    function calcAmountOutFromEth(WenToken token, uint256 amountIn) external view returns (uint256 amountOut) {
        if (amountIn == 0) revert InvalidAmountIn();

        uint256 fee = amountIn * feeRate_ / FEE_DENOMINATOR;
        amountIn -= fee;

        uint256 newVirtualEthReserve = pools_[token].virtualEthReserve + amountIn;
        uint256 newVirtualTokenReserve = K_ / newVirtualEthReserve;
        amountOut = pools_[token].virtualTokenReserve - newVirtualTokenReserve;

        if (amountOut > pools_[token].tokenReserve) {
            amountOut = pools_[token].tokenReserve;
        }
    }

    /*///////////////////////////////////////////
    //             Storage  Getters            //
    ///////////////////////////////////////////*/

    function getPool(WenToken token) external view returns (Pool memory) {
        return pools_[token];
    }

    function getPoolsAll() external view returns (Pool[] memory) {
        WenToken[] memory tokens = wenLedger_.getTokens();
        Pool[] memory pools = new Pool[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            pools[i] = pools_[tokens[i]];
        }

        return pools;
    }
}
