// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import { ImmutableState } from "./ImmutableState.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IPair } from "./interfaces/IPair.sol";
import { IPairMintCallback } from "./interfaces/callback/IPairMintCallback.sol";
import { ISwapCallback } from "./interfaces/callback/ISwapCallback.sol";

import { Balance } from "../libraries/Balance.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { SafeCast } from "../libraries/SafeCast.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";

abstract contract Pair is ImmutableState, ReentrancyGuard, IPair {
  /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

  event Mint(uint256 amount0In, uint256 amount1In, uint256 liquidity);

  event Burn(uint256 amount0Out, uint256 amount1Out, uint256 liquidity, address indexed to);

  event Swap(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In, address indexed to);

  /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

  error InvariantError();

  error InsufficientOutputError();

  /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @inheritdoc IPair
  uint120 public override reserve0;

  /// @inheritdoc IPair
  uint120 public override reserve1;

  /// @inheritdoc IPair
  uint256 public override totalLiquidity;

  /*//////////////////////////////////////////////////////////////
                            SWAP FEE STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant FEE_DENOMINATOR = 1e6;
    uint256 private constant SWAP_FEE_VALUE = 3000; // 30 bps (3000/1e6)

    /// @inheritdoc IPair
    function swapFee() external pure override returns (uint256) {
        return SWAP_FEE_VALUE;
    }

  /*//////////////////////////////////////////////////////////////
                              PAIR LOGIC
    //////////////////////////////////////////////////////////////*/

  /*/////////////////////////////////////////////////////////////////////////////
  //  The capped power-4 invariant is x + y * U >= (3y^(4/3) / 8L) * U^4       //
  //  and is implemented in a + b >= c + d where:                              //
  //  a = scale0 * 1e18 = x * 1e18                                             //
  //  b = scale1 * upperBound = y * U                                          //
  //  c = (scale1 * 4/3) * 3 / 8 = 3y^(4/3) / 8                                //
  //  d = upperBound ** 4 = U^4                                                //
  /////////////////////////////////////////////////////////////////////////////*/

  /// @inheritdoc IPair
  function invariant(uint256 amount0, uint256 amount1, uint256 liquidity) public view override returns (bool) {
    if (liquidity == 0) return (amount0 == 0 && amount1 == 0);

    uint256 scale0 = FullMath.mulDiv(amount0 * token0Scale, 1e18, liquidity);
    uint256 scale1 = FullMath.mulDiv(amount1 * token1Scale, 1e18, liquidity);

    if (scale1 > 2 * upperBound) revert InvariantError();

    uint256 a = scale0 * 1e18;
    uint256 b = scale1 * upperBound;
    uint256 c = (3 * scale1 * FullMath.mulDiv(scale1, scale1, 1e18)) / 8;
    uint256 d = upperBound ** 4;

    return a + b >= c + d;
  }

  /// @dev assumes liquidity is non-zero
  function mint(uint256 liquidity, bytes calldata data) internal {
    uint120 _reserve0 = reserve0; // SLOAD
    uint120 _reserve1 = reserve1; // SLOAD
    uint256 _totalLiquidity = totalLiquidity; // SLOAD

    uint256 balance0Before = Balance.balance(token0);
    uint256 balance1Before = Balance.balance(token1);
    IPairMintCallback(msg.sender).pairMintCallback(liquidity, data);
    uint256 amount0In = Balance.balance(token0) - balance0Before;
    uint256 amount1In = Balance.balance(token1) - balance1Before;

    if (!invariant(_reserve0 + amount0In, _reserve1 + amount1In, _totalLiquidity + liquidity)) {
      revert InvariantError();
    }

    reserve0 = _reserve0 + SafeCast.toUint120(amount0In); // SSTORE
    reserve1 = _reserve1 + SafeCast.toUint120(amount1In); // SSTORE
    totalLiquidity = _totalLiquidity + liquidity; // SSTORE

    emit Mint(amount0In, amount1In, liquidity);
  }

  /// @dev assumes liquidity is non-zero
  function burn(address to, uint256 liquidity) internal returns (uint256 amount0, uint256 amount1) {
    uint120 _reserve0 = reserve0; // SLOAD
    uint120 _reserve1 = reserve1; // SLOAD
    uint256 _totalLiquidity = totalLiquidity; // SLOAD

    amount0 = FullMath.mulDiv(_reserve0, liquidity, _totalLiquidity);
    amount1 = FullMath.mulDiv(_reserve1, liquidity, _totalLiquidity);
    if (amount0 == 0 && amount1 == 0) revert InsufficientOutputError();

    if (amount0 > 0) SafeTransferLib.safeTransfer(token0, to, amount0);
    if (amount1 > 0) SafeTransferLib.safeTransfer(token1, to, amount1);

    // Extra check of the invariant
    if (!invariant(_reserve0 - amount0, _reserve1 - amount1, _totalLiquidity - liquidity)) revert InvariantError();

    reserve0 = _reserve0 - SafeCast.toUint120(amount0); // SSTORE
    reserve1 = _reserve1 - SafeCast.toUint120(amount1); // SSTORE
    totalLiquidity = _totalLiquidity - liquidity; // SSTORE

    emit Burn(amount0, amount1, liquidity, to);
  }

  /// @inheritdoc IPair
  function swap(address to, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external override nonReentrant {
    if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputError();

    uint120 _reserve0 = reserve0; // SLOAD
    uint120 _reserve1 = reserve1; // SLOAD

    if (amount0Out > 0) SafeTransferLib.safeTransfer(token0, to, amount0Out);
    if (amount1Out > 0) SafeTransferLib.safeTransfer(token1, to, amount1Out);

    uint256 balance0Before = Balance.balance(token0);
    uint256 balance1Before = Balance.balance(token1);
    ISwapCallback(msg.sender).swapCallback(amount0Out, amount1Out, data);
    uint256 amount0In = Balance.balance(token0) - balance0Before;
    uint256 amount1In = Balance.balance(token1) - balance1Before;

    // Calculate the swap fee amounts
    uint256 fee0 = FullMath.mulDiv(amount0In, SWAP_FEE_VALUE, FEE_DENOMINATOR);
    uint256 fee1 = FullMath.mulDiv(amount1In, SWAP_FEE_VALUE, FEE_DENOMINATOR);

    // Adjust the input amounts by subtracting the swap fees
    amount0In -= fee0;
    amount1In -= fee1;

    if (!invariant(_reserve0 + amount0In - amount0Out, _reserve1 + amount1In - amount1Out, totalLiquidity)) {
      revert InvariantError();
    }

    reserve0 = _reserve0 + SafeCast.toUint120(amount0In) - SafeCast.toUint120(amount0Out); // SSTORE
    reserve1 = _reserve1 + SafeCast.toUint120(amount1In) - SafeCast.toUint120(amount1Out); // SSTORE

    emit Swap(amount0Out, amount1Out, amount0In, amount1In, to);
  }
}
