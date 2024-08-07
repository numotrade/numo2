// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

// import { Lendgine } from "../src/core/Lendgine.sol";
// import { QFMM } from "../src/core/QFMM.sol";
// import { TestHelper } from "./utils/TestHelper.sol";

// contract CollectTest is TestHelper {
//   event Collect(address indexed owner, address indexed to, uint256 amount);

//   function setUp() external {
//     _setUp();
//   }

//   function testZeroCollect() external {
//     uint256 collateral = lendgine.collect(alice, 0);
//     assertEq(0, collateral);

//     collateral = lendgine.collect(alice, 1 ether);
//     assertEq(0, collateral);
//   }

//   function testCollectBasic() external {
//     _deposit(alice, alice, 1 ether, 8 ether, 1 ether);
//     _mint(address(this), address(this), 5 ether);

//     vm.warp(365 days + 1);

//     uint256 borrowRate = lendgine.getBorrowRate(0.5 ether, 1 ether);
//     uint256 lpDilution = borrowRate / 2; // 0.5 lp for one year

//     vm.prank(alice);
//     lendgine.accruePositionInterest();

//     vm.prank(alice);
//     uint256 collateral = lendgine.collect(alice, lpDilution * 5);

//     // check return data
//     assertEq(lpDilution * 5, collateral);

//     // check position
//     (,, uint256 tokensOwed) = lendgine.positions(alice);
//     assertEq(lpDilution * 5, tokensOwed);

//     // check token balances
//     assertEq(lpDilution * 5, token1.balanceOf(alice));
//   }

//   function testOverCollect() external {
//     _deposit(alice, alice, 1 ether, 8 ether, 1 ether);
//     _mint(address(this), address(this), 5 ether);

//     vm.warp(365 days + 1);

//     uint256 borrowRate = lendgine.getBorrowRate(0.5 ether, 1 ether);
//     uint256 lpDilution = borrowRate / 2; // 0.5 lp for one year

//     vm.prank(alice);
//     lendgine.accruePositionInterest();

//     vm.prank(alice);
//     uint256 collateral = lendgine.collect(alice, 100 ether);

//     // check return data
//     assertEq(lpDilution * 10, collateral);

//     // check position
//     (,, uint256 tokensOwed) = lendgine.positions(alice);
//     assertEq(0, tokensOwed);

//     // check token balances
//     assertEq(lpDilution * 10, token1.balanceOf(alice));
//   }

//   function testEmit() external {
//     _deposit(alice, alice, 1 ether, 8 ether, 1 ether);
//     _mint(address(this), address(this), 5 ether);

//     vm.warp(365 days + 1);

//     uint256 borrowRate = lendgine.getBorrowRate(0.5 ether, 1 ether);
//     uint256 lpDilution = borrowRate / 2; // 0.5 lp for one year

//     vm.prank(alice);
//     lendgine.accruePositionInterest();

//     vm.prank(alice);
//     vm.expectEmit(true, true, false, true, address(lendgine));
//     emit Collect(alice, alice, lpDilution * 10);
//     lendgine.collect(alice, lpDilution * 10);
//   }
// }
