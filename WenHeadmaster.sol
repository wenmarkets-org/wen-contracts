// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IUniswapV2Router02 } from "./interfaces/IUniswapV2Router02.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";
import { WenToken } from "./WenToken.sol";
import { WenFoundry } from "./WenFoundry.sol";

error Forbidden();
error InvalidAmountToken();
error InvalidAmountEth();

/// @title A Wen protocol graduation strategy for bootstrapping liquidity on uni-v2 AMMs.
/// @author strobie <@0xstrobe>
/// @notice This contract may be replaced by other strategies in the future.
contract WenHeadmaster {
    WenFoundry public immutable wenFoundry;
    IUniswapV2Router02 public immutable uniswapV2Router02;
    IUniswapV2Factory public immutable uniswapV2Factory;

    address public constant liquidityOwner = address(0);

    WenToken[] public alumni;

    constructor(WenFoundry _wenFoundry, IUniswapV2Router02 _uniswapV2Router02) {
        wenFoundry = _wenFoundry;
        uniswapV2Router02 = IUniswapV2Router02(payable(_uniswapV2Router02));
        uniswapV2Factory = IUniswapV2Factory(uniswapV2Router02.factory());
    }

    modifier onlyWenFoundry() {
        if (msg.sender != address(wenFoundry)) revert Forbidden();
        _;
    }

    event Executed(WenToken token, uint256 indexed poolId, uint256 amountToken, uint256 amountETH, address indexed owner);

    function execute(WenToken token, uint256 amountToken, uint256 amountEth)
        external
        payable
        onlyWenFoundry
        returns (uint256 poolId, uint256 _amountToken, uint256 _amountETH)
    {
        if (amountToken == 0) revert InvalidAmountToken();
        if (amountEth == 0 || msg.value != amountEth) revert InvalidAmountEth();

        SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amountToken);
        SafeTransferLib.safeApprove(token, address(uniswapV2Router02), amountToken);

        address pair = uniswapV2Factory.createPair(address(token), uniswapV2Router02.WETH());
        poolId = uint256(uint160(pair));
        (_amountToken, _amountETH,) = uniswapV2Router02.addLiquidityETH{ value: amountEth }(address(token), amountToken, 0, 0, liquidityOwner, block.timestamp);

        alumni.push(token);

        emit Executed(token, poolId, _amountToken, _amountETH, liquidityOwner);
    }

    /*///////////////////////////////////////////
    //             Storage  Getters            //
    ///////////////////////////////////////////*/

    function getAlumni() external view returns (WenToken[] memory) {
        return alumni;
    }
}
