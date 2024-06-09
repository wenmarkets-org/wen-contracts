## Wen Protocol

**The Wen Protocol is a set of smart contracts to simplify permissionless liquidity bootstrapping for users.**

The Wen protocol (aka. Wen Markets, Wen) consists of:

- **WenFoundry**: The Wen protocol singleton AMM with a custom bonding curve built-in.
- **WenHeadmaster**: The replaceable Wen protocol liquidity bootstrapping strategy.
- **WenLedger**: The Wen protocol user activity bookkeeper.
- **WenLens**: A on-chain data lookup utility for the Wen protocol frontend.
- **WenToken**: The Wen protocol ERC20 token template.

## Frontend dApp

https://wen.markets/

## Documentation

### WenFoundry

The WenFoundry is a singleton AMM with a custom bonding curve built-in. It is the core of the Wen protocol.

There is an "owner" role for the WenFoundry, which can pause trading, set fees, and set the graduation strategy, but cannot withdraw funds or modify the bonding curve.

WenFoundry has a custom bonding curve, based on the K=X\*Y formula and a certain initial value for X and Y as virtual liquidity.

When the market cap of a token on WenFoundry hits a certain value, we consider this token is graduated from Wen. The liquidity of this pool will be processed by a "headmaster" contract which will graduate the token into a public AMM, such as Ambient, Uniswap, or Balancer.

Unlike similar platforms who manually graduates tokens and have a permission risk, the Wen protocol will automatically graduate whenever the market cap is hit, with no delay and is atomic with the last trade that made the market cap cross the threshold.

### WenHeadmaster

The WenHeadmaster is a replaceable liquidity bootstrapping strategy for the WenFoundry. It can be replaced by the owner of the WenFoundry to upgrade the liquidity bootstrapping strategy.

Part of this graduation strategy also include handling locking or burning the liquidity.

The current WenHeadmaster is a strategy that graduates the token into a Uniswap V2 compatible AMM.

### WenLedger

The WenLedger is the user activity bookkeeper for the Wen protocol. It records the user's trading history and provides a way to query the such data. Since the current version of the protocol is not deployed on gas-expensive networks, this contract is designed to make data more available from onchain to reduce the need for off-chain indexing.

Most query functions have a `limit` parameter to limit the number of records returned. This is to improve the query performance and prevent the frontend from DDoSing the RPC nodes as the data grows.

### WenLens

The WenLens is a on-chain data lookup utility for the Wen protocol frontend. It provides a way to query the onchain data like ETH price and token price in ETH or USD. It is an optional contract that is not required for the protocol to function.

### WenToken

The WenToken is the ERC20 token template for the Wen protocol. The token allowance is restricted to only the WenFoundry contract until graduation, so before that, the token is transferable but not tradable.

## Deployment

### Polygon

| Contract      | Address                                    |
| ------------- | ------------------------------------------ |
| WenFoundry    | 0x3bB94837A91E22A134053B9F38728E27055ec3d1 |
| WenLedger     | 0x5574d1e44eFcc5530409fbE1568f335DaF83951c |
| WenHeadmaster | 0xCc5e02012E600B88d496f5406eC810917B1169f9 |
| WenLens       | 0xC0Dbd3dDEad176A0066c7633CA7BE12973Da75Ca |

## Acknowledgements

This project is made possible by a grant from the [Polygon](https://polygon.technology/) team. The author would like to thank the Polygon team for their support!

The logo and mascot of this project, Pauly, originates from the Paulygon project by [Jack](https://x.com/jackmelnick_), a homage to the Polygon ecosystem. Thank you for allowing us to feature Pauly in our project!

## License

The Wen Protocol is currently unlicensed and is not available for public use. Please contact the project owner for more information.
