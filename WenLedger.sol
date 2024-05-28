// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { WenFoundry } from "./WenFoundry.sol";
import { WenToken } from "./WenToken.sol";

error NotFoundry();

/// @title The Wen protocol user activity bookkeeper.
/// @author strobie <@0xstrobe>
/// @notice Since this version of the protocol is not deployed on gas-expensive networks, this contract is designed to make data more available from onchain.
contract WenLedger {
    struct Stats {
        uint256 totalVolume;
        uint256 totalLiquidityBootstrapped;
        uint256 totalTokensCreated;
        uint256 totalTokensGraduated;
        uint256 totalTrades;
    }

    struct Trade {
        WenToken token;
        address maker;
        uint256 amountIn;
        uint256 amountOut;
        bool isBuy;
        uint128 timestamp;
        uint128 blockNumber;
    }

    uint256 public totalVolume;
    uint256 public totalLiquidityBootstrapped;

    mapping(address => WenToken[]) public tokensCreatedBy;
    mapping(address => WenToken[]) public tokensTradedBy;
    mapping(WenToken => mapping(address => bool)) public hasTraded;

    WenToken[] public tokensCreated;
    WenToken[] public tokensGraduated;
    mapping(WenToken => bool) public isGraduated;

    Trade[] public trades;
    mapping(WenToken => uint256[]) public tradesByToken;
    mapping(address => uint256[]) public tradesByUser;

    WenFoundry public immutable wenFoundry;

    constructor() {
        wenFoundry = WenFoundry(msg.sender);
    }

    modifier onlyFoundry() {
        if (msg.sender != address(wenFoundry)) revert NotFoundry();
        _;
    }

    /// Add a token to the list of tokens created by a user
    /// @param token The token to add
    /// @param user The user to add the token for
    /// @notice This method should only be called once per token creation
    function addCreation(WenToken token, address user) public onlyFoundry {
        tokensCreatedBy[user].push(token);
        tokensCreated.push(token);
    }

    /// Add a trade to the ledger
    /// @param trade The trade to add
    function addTrade(Trade memory trade) public onlyFoundry {
        uint256 tradeId = trades.length;
        trades.push(trade);
        tradesByToken[trade.token].push(tradeId);
        tradesByUser[trade.maker].push(tradeId);
        totalVolume += trade.isBuy ? trade.amountIn : trade.amountOut;

        if (hasTraded[trade.token][trade.maker]) return;

        tokensTradedBy[trade.maker].push(trade.token);
        hasTraded[trade.token][trade.maker] = true;
    }

    /// Add a token to the list of graduated tokens
    /// @param token The token to add
    /// @notice This method should only be called once per token graduation
    function addGraduation(WenToken token, uint256 amountEth) public onlyFoundry {
        tokensGraduated.push(token);
        isGraduated[token] = true;
        totalLiquidityBootstrapped += amountEth;
    }

    /*///////////////////////////////////////////
    //             Storage  Getters            //
    ///////////////////////////////////////////*/

    function getTokensCreatedBy(address user) public view returns (WenToken[] memory) {
        return tokensCreatedBy[user];
    }

    function getTokensTradedBy(address user) public view returns (WenToken[] memory) {
        return tokensTradedBy[user];
    }

    function getTokens() public view returns (WenToken[] memory) {
        return tokensCreated;
    }

    function getToken(uint256 tokenId) public view returns (WenToken) {
        return tokensCreated[tokenId];
    }

    function getTokensLength() public view returns (uint256) {
        return tokensCreated.length;
    }

    function getTokensGraduated() public view returns (WenToken[] memory) {
        return tokensGraduated;
    }

    function getTokenGraduated(uint256 tokenId) public view returns (WenToken) {
        return tokensGraduated[tokenId];
    }

    function getTokensGraduatedLength() public view returns (uint256) {
        return tokensGraduated.length;
    }

    function getTradesAll() public view returns (Trade[] memory) {
        return trades;
    }

    function getTrade(uint256 tradeId) public view returns (Trade memory) {
        return trades[tradeId];
    }

    function getTradesLength() public view returns (uint256) {
        return trades.length;
    }

    function getTradesByTokenLength(WenToken token) public view returns (uint256) {
        return tradesByToken[token].length;
    }

    function getTradeIdsByToken(WenToken token) public view returns (uint256[] memory) {
        return tradesByToken[token];
    }

    function getTradesByUserLength(address user) public view returns (uint256) {
        return tradesByUser[user].length;
    }

    function getTradeIdsByUser(address user) public view returns (uint256[] memory) {
        return tradesByUser[user];
    }

    function getStats() public view returns (Stats memory) {
        return Stats({
            totalVolume: totalVolume,
            totalLiquidityBootstrapped: totalLiquidityBootstrapped,
            totalTokensCreated: tokensCreated.length,
            totalTokensGraduated: tokensGraduated.length,
            totalTrades: trades.length
        });
    }
}
