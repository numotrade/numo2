// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import { Multicall } from "./Multicall.sol";
import { Payment } from "./Payment.sol";
import { SelfPermit } from "./SelfPermit.sol";
import { ILendgine } from "../core/interfaces/ILendgine.sol";
import { IQFMMMintCallback } from "../core/interfaces/callback/IQFMMMintCallback.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { LendgineAddress } from "./libraries/LendgineAddress.sol";


contract LiquidityManager is Multicall, Payment, SelfPermit, IQFMMMintCallback {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event AddLiquidity(
        address indexed from,
        address indexed lendgine,
        uint256 liquidity,
        uint256 size,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );

    event RemoveLiquidity(
        address indexed from,
        address indexed lendgine,
        uint256 liquidity,
        uint256 size,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );

    event Collect(address indexed from, address indexed lendgine, uint256 amount, address indexed to);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error LivelinessError();
    error AmountError();
    error ValidationError();
    error PositionInvalidError();
    error CollectError();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    address public immutable factory;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _factory, address _weth) Payment(_weth) {
        factory = _factory;
    }

    /*//////////////////////////////////////////////////////////////
                           LIVELINESS MODIFIER
    //////////////////////////////////////////////////////////////*/
    modifier checkDeadline(uint256 deadline) {
        if (deadline < block.timestamp) revert LivelinessError();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CALLBACK
    //////////////////////////////////////////////////////////////*/
    struct QFMMMintCallbackData {
        address token0;
        address token1;
        uint256 token0Exp;
        uint256 token1Exp;
        uint256 strike;
        uint256 amount0;
        uint256 amount1;
        address payer;
    }

    /// @notice callback that sends the underlying tokens for the specified amount of liquidity shares
    function QFMMMintCallback(uint256, bytes calldata data) external {
        QFMMMintCallbackData memory decoded = abi.decode(data, (QFMMMintCallbackData));

        address lendgine = LendgineAddress.computeAddress(
            factory, decoded.token0, decoded.token1, decoded.token0Exp, decoded.token1Exp, decoded.strike
        );
        if (lendgine != msg.sender) revert ValidationError();

        if (decoded.amount0 > 0) pay(decoded.token0, decoded.payer, msg.sender, decoded.amount0);
        if (decoded.amount1 > 0) pay(decoded.token1, decoded.payer, msg.sender, decoded.amount1);
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY MANAGER LOGIC
    //////////////////////////////////////////////////////////////*/
    struct AddLiquidityParams {
        address token0;
        address token1;
        uint256 token0Exp;
        uint256 token1Exp;
        uint256 strike;
        uint256 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 sizeMin;
        address recipient;
        uint256 deadline;
    }

    /// @notice Add liquidity to a liquidity position
    function addLiquidity(AddLiquidityParams calldata params) external payable checkDeadline(params.deadline) {
        address lendgine = LendgineAddress.computeAddress(
            factory, params.token0, params.token1, params.token0Exp, params.token1Exp, params.strike
        );

        uint256 r0 = ILendgine(lendgine).reserve0();
        uint256 r1 = ILendgine(lendgine).reserve1();
        uint256 totalLiquidity = ILendgine(lendgine).totalLiquidity();

        uint256 amount0;
        uint256 amount1;

        if (totalLiquidity == 0) {
            amount0 = params.amount0Min;
            amount1 = params.amount1Min;
        } else {
            amount0 = FullMath.mulDivRoundingUp(params.liquidity, r0, totalLiquidity);
            amount1 = FullMath.mulDivRoundingUp(params.liquidity, r1, totalLiquidity);
        }

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert AmountError();

        uint256 size = ILendgine(lendgine).deposit(
            params.recipient,
            params.liquidity,
            abi.encode(
                QFMMMintCallbackData({
                    token0: params.token0,
                    token1: params.token1,
                    token0Exp: params.token0Exp,
                    token1Exp: params.token1Exp,
                    strike: params.strike,
                    amount0: amount0,
                    amount1: amount1,
                    payer: msg.sender
                })
            )
        );
        if (size < params.sizeMin) revert AmountError();

        emit AddLiquidity(msg.sender, lendgine, params.liquidity, size, amount0, amount1, params.recipient);
    }

    struct RemoveLiquidityParams {
        address token0;
        address token1;
        uint256 token0Exp;
        uint256 token1Exp;
        uint256 strike;
        uint256 size;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Removes from a liquidity position
    function removeLiquidity(RemoveLiquidityParams calldata params) external checkDeadline(params.deadline) {
        address lendgine = LendgineAddress.computeAddress(
            factory, params.token0, params.token1, params.token0Exp, params.token1Exp, params.strike
        );

        address recipient = params.recipient == address(0) ? msg.sender : params.recipient;

        (uint256 amount0, uint256 amount1, uint256 liquidity) = ILendgine(lendgine).withdraw(recipient, params.size);
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) revert AmountError();

        emit RemoveLiquidity(msg.sender, lendgine, liquidity, params.size, amount0, amount1, recipient);
    }

    struct CollectParams {
        address lendgine;
        address recipient;
        uint256 amountRequested;
    }

    /// @notice Collects interest owed to the caller's liquidity position
    function collect(CollectParams calldata params) external returns (uint256 amount) {
        ILendgine(params.lendgine).accruePositionInterest();

        address recipient = params.recipient == address(0) ? msg.sender : params.recipient;

        amount = ILendgine(params.lendgine).collect(msg.sender, params.amountRequested);

        emit Collect(msg.sender, params.lendgine, amount, recipient);
    }

    /*//////////////////////////////////////////////////////////////
                         MINT AND BURN WRAPPERS
    //////////////////////////////////////////////////////////////*/
    struct MintParams {
        address recipient;
        uint256 collateral;
        bytes data;
    }

    /// @notice Mint liquidity provider shares
    function mint(MintParams calldata params) external returns (uint256 shares) {
        shares = ILendgine(factory).mint(params.recipient, params.collateral, params.data);
    }

    struct BurnParams {
        address recipient;
        bytes data;
    }

    /// @notice Burn liquidity provider shares
    function burn(BurnParams calldata params) external returns (uint256 collateral) {
        collateral = ILendgine(factory).burn(params.recipient, params.data);
    }
}
