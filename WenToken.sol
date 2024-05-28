// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { WenFoundry } from "./WenFoundry.sol";

error NotWenFoundry();
error NotApprovable();

/// @title The Wen protocol ERC20 token template.
/// @author strobie <@0xstrobe>
/// @notice The token allowance is restricted to only the WenFoundry contract until graduation, so before that, the token is transferable but not tradable.
/// @dev The view functions are intended for frontend usage with limit <<< n instead of limit ≈ n, so the sorting algos are effectively O(n). Data is stored onchain for improved UX.
contract WenToken is ERC20 {
    struct Metadata {
        WenToken token;
        string name;
        string symbol;
        string description;
        string extended;
        address creator;
        bool isGraduated;
        uint256 mcap;
    }

    string public description;
    string public extended;
    WenFoundry public immutable wenFoundry;
    address public immutable creator;

    address[] public holders;
    mapping(address => bool) public isHolder;

    /// @notice Locked before graduation to restrict trading to WenFoundry
    bool public isApprovable = false;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _supply,
        string memory _description,
        string memory _extended,
        address _wenFoundry,
        address _creator
    ) ERC20(_name, _symbol, _decimals) {
        description = _description;
        extended = _extended;
        wenFoundry = WenFoundry(_wenFoundry);
        creator = _creator;

        _mint(msg.sender, _supply);
        _addHolder(msg.sender);
    }

    function _addHolder(address holder) private {
        if (!isHolder[holder]) {
            holders.push(holder);
            isHolder[holder] = true;
        }
    }

    function getMetadata() public view returns (Metadata memory) {
        WenFoundry.Pool memory pool = wenFoundry.getPool(this);
        return Metadata(WenToken(address(this)), this.name(), this.symbol(), description, extended, creator, isGraduated(), pool.lastMcapInEth);
    }

    function isGraduated() public view returns (bool) {
        WenFoundry.Pool memory pool = wenFoundry.getPool(this);
        return pool.headmaster != address(0);
    }

    function setIsApprovable(bool _isApprovable) public {
        if (msg.sender != address(wenFoundry)) revert NotWenFoundry();
        isApprovable = _isApprovable;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _addHolder(to);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Pre-approve WenFoundry for improved UX
        if (allowance[from][address(wenFoundry)] != type(uint256).max) {
            allowance[from][address(wenFoundry)] = type(uint256).max;
        }
        _addHolder(to);
        return super.transferFrom(from, to, amount);
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (!isApprovable) revert NotApprovable();

        return super.approve(spender, amount);
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public override {
        if (!isApprovable) revert NotApprovable();

        super.permit(owner, spender, value, deadline, v, r, s);
    }

    /// Get all addresses who have ever held the token with their balances
    /// @return The holders and their balances
    /// @notice Some holders may have a zero balance
    function getHoldersWithBalance() public view returns (address[] memory, uint256[] memory) {
        uint256 length = holders.length;
        uint256[] memory balances = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            address holder = holders[i];
            uint256 balance = balanceOf[holder];
            balances[i] = balance;
        }

        return (holders, balances);
    }

    /// Get all addresses who have ever held the token
    /// @return The holders
    /// @notice Some holders may have a zero balance
    function getHolders() public view returns (address[] memory) {
        return holders;
    }

    /// Get the number of all addresses who have ever held the token
    /// @return The number of holders
    /// @notice Some holders may have a zero balance
    function getHoldersLength() public view returns (uint256) {
        return holders.length;
    }
}
