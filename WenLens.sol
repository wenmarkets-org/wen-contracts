// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { WenFoundry } from "./WenFoundry.sol";
import { WenLedger } from "./WenLedger.sol";
import { WenToken } from "./WenToken.sol";

/// @title A on-chain data lookup utility for the Wen protocol frontend.
/// @author strobie <@0xstrobe>
contract WenLens {
    using FixedPointMathLib for uint256;

    WenFoundry public immutable wenFoundry;
    IUniswapV2Pair public immutable usdcWethPair;
    ERC20 public immutable usdc;
    ERC20 public immutable weth;
    WenLedger public immutable wenLedger;

    constructor(WenFoundry _wenFoundry, IUniswapV2Pair _usdcWethPair, ERC20 _usdc, ERC20 _weth) {
        wenFoundry = _wenFoundry;
        usdcWethPair = _usdcWethPair;
        usdc = _usdc;
        weth = _weth;
        wenLedger = wenFoundry.wenLedger_();
    }

    function getEthPriceInUsdWad() public view returns (uint256) {
        uint256 ethBalance = weth.balanceOf(address(usdcWethPair));
        uint256 usdcBalance = usdc.balanceOf(address(usdcWethPair)) * 1e18 / (10 ** usdc.decimals());

        return usdcBalance.divWadDown(ethBalance);
    }

    function getTokenPriceInEthWad(WenToken token) public view returns (uint256) {
        // lastPrice is in WAD, eth/token
        WenFoundry.Pool memory pool = wenFoundry.getPool(token);

        return pool.lastPrice;
    }

    function getTokenPriceInUsdWad(WenToken token) public view returns (uint256) {
        uint256 lastPrice = getTokenPriceInEthWad(token);
        uint256 ethPriceInUsdWad = getEthPriceInUsdWad();

        return lastPrice.mulWadUp(ethPriceInUsdWad);
    }

    /*////////////////////////////////////////////
    //////////////// LEDGER QUERIES //////////////
    ////////////////////////////////////////////*/

    /// Get the latest N trades in chronologically reversed order
    /// @param limit The maximum number of trades to return
    /// @return The latest trades
    /// @notice The trades are stored in a sequential array
    function getTrades(uint256 limit) public view returns (WenLedger.Trade[] memory) {
        uint256 length = wenLedger.getTradesLength();
        uint256 count = limit < length ? limit : length;
        WenLedger.Trade[] memory result = new WenLedger.Trade[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = wenLedger.getTrade(length - i - 1);
        }

        return result;
    }

    /// Get the latest N trades for a token in chronologically reversed order
    /// @param token The token to get trades for
    /// @param limit The maximum number of trades to return
    /// @return The latest trades for the token
    /// @notice The trades are stored in a sequential array
    function getTradesByToken(WenToken token, uint256 limit) public view returns (WenLedger.Trade[] memory) {
        uint256[] memory tradeIds = wenLedger.getTradeIdsByToken(token);
        uint256 length = tradeIds.length;
        uint256 count = limit < length ? limit : length;
        WenLedger.Trade[] memory result = new WenLedger.Trade[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = wenLedger.getTrade(tradeIds[length - i - 1]);
        }

        return result;
    }

    /// Get the latest N trades for a user in chronologically reversed order
    /// @param user The user to get trades for
    /// @param limit The maximum number of trades to return
    /// @return The latest trades for the user
    /// @notice The trades are stored in a sequential array
    function getTradesByUser(address user, uint256 limit) public view returns (WenLedger.Trade[] memory) {
        uint256[] memory tradeIds = wenLedger.getTradeIdsByUser(user);
        uint256 length = tradeIds.length;
        uint256 count = limit < length ? limit : length;
        WenLedger.Trade[] memory result = new WenLedger.Trade[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = wenLedger.getTrade(tradeIds[length - i - 1]);
        }

        return result;
    }

    /// Get the latest N trades for a user and token pair in chronologically reversed order
    /// @param user The user to get trades for
    /// @param token The token to get trades for
    /// @param limit The maximum number of trades to return
    /// @return The latest trades for the user and token pair
    /// @notice The trades are stored in a sequential array
    function getTradesByUserAndToken(address user, WenToken token, uint256 limit) public view returns (WenLedger.Trade[] memory) {
        uint256[] memory tradeIds = wenLedger.getTradeIdsByUser(user);
        uint256 length = tradeIds.length;
        uint256 count = limit < length ? limit : length;
        WenLedger.Trade[] memory result_ = new WenLedger.Trade[](count);
        uint256 resultIndex = 0;

        for (uint256 i = 0; i < count; i++) {
            WenLedger.Trade memory trade = wenLedger.getTrade(tradeIds[length - i - 1]);
            if (trade.token == token) {
                result_[resultIndex] = trade;
                resultIndex++;
            }
        }

        WenLedger.Trade[] memory result = new WenLedger.Trade[](resultIndex);
        for (uint256 i = 0; i < resultIndex; i++) {
            result[i] = result_[i];
        }

        return result;
    }

    /// Get the total volume of a token traded in ETH
    /// @param token The token to get the volume for
    /// @return The total volume of the token traded in ETH
    function getVolumeByToken(WenToken token) public view returns (uint256) {
        uint256[] memory tradeIds = wenLedger.getTradeIdsByToken(token);
        uint256 length = tradeIds.length;
        uint256 volume = 0;

        for (uint256 i = 0; i < length; i++) {
            WenLedger.Trade memory trade = wenLedger.getTrade(tradeIds[i]);
            volume += trade.isBuy ? trade.amountIn : trade.amountOut;
        }

        return volume;
    }

    /// Get the total volume of a user in ETH
    /// @param user The user to get the volume for
    /// @return The total volume of the user in ETH
    function getVolumeByUser(address user) public view returns (uint256) {
        uint256[] memory tradeIds = wenLedger.getTradeIdsByUser(user);
        uint256 length = tradeIds.length;
        uint256 volume = 0;

        for (uint256 i = 0; i < length; i++) {
            // WenLedger.Trade memory trade = trades[tradeIds[i]];
            WenLedger.Trade memory trade = wenLedger.getTrade(tradeIds[i]);
            volume += trade.isBuy ? trade.amountIn : trade.amountOut;
        }

        return volume;
    }

    /// Get the total volume of a user and token pair in ETH
    /// @param user The user to get the volume for
    /// @param token The token to get the volume for
    /// @return The total volume of the user and token pair in ETH
    function getVolumeByUserAndToken(address user, WenToken token) public view returns (uint256) {
        uint256[] memory tradeIds = wenLedger.getTradeIdsByUser(user);
        uint256 length = tradeIds.length;
        uint256 volume = 0;

        for (uint256 i = 0; i < length; i++) {
            WenLedger.Trade memory trade = wenLedger.getTrade(tradeIds[i]);
            if (trade.token == token) {
                volume += trade.isBuy ? trade.amountIn : trade.amountOut;
            }
        }

        return volume;
    }

    /// @notice Get the metadata of the latest N tokens created in chronologically reversed order.
    /// @param limit The maximum number of tokens to return.
    /// @return The latest tokens created.
    function getLatestTokens(uint256 limit) external view returns (WenToken.Metadata[] memory) {
        uint256 length = wenLedger.getTokensLength();
        uint256 count = limit < length ? limit : length;
        WenToken.Metadata[] memory result = new WenToken.Metadata[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = wenLedger.getToken(length - i - 1).getMetadata();
        }

        return result;
    }
}
