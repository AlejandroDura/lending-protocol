// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {StakingRewards} from "src/StakingRewards.sol";
import {DepositToken} from "src/tokens/DepositToken.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {StakingHandler} from "test/fuzz/StakingHandler.t.sol";

contract StakingInvariants is StdInvariant, Test {
    address[] public suppliers;
    address[] public borrowers;
    uint256 private constant EIGHTEEN_PRECISION = 1e18;

    HelperConfig config;
    DepositToken public depositToken;
    ERC20Mock public usdcToken;
    StakingRewards public staking;
    StakingHandler public handler;

    function setUp() external {
        for (uint256 i = 0; i < 10; i++) {
            address supplier = makeAddr(string(abi.encodePacked("supplier", i)));
            vm.deal(supplier, 1_000_000 ether);
            suppliers.push(supplier);
        }

        for (uint256 i = 0; i < 5; i++) {
            address borrower = makeAddr(string(abi.encodePacked("borrower", i)));
            vm.deal(borrower, 1_000_000 ether);
            borrowers.push(borrower);
        }

        staking = new StakingRewards(address(this));
        handler = new StakingHandler(staking, suppliers, borrowers);
        staking.transferOwnership(address(handler));
        targetContract(address(handler));
        //targetContract(address(staking));
        // bytes4[] memory selectors = new bytes4[](1);
        // selectors[0] = StakingHandler.addLiquidity.selector;

        // targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_totalUserSharesEqualsToTotalShares() public {
        uint256 totalSuppliersShares;
        for (uint256 i = 0; i < suppliers.length; i++) {
            totalSuppliersShares += staking.getUserShare(suppliers[i]);
        }

        if (staking.getTotalShares() > 0) {
            assertEq(staking.getTotalShares(), totalSuppliersShares, "TOTAL USER SHARES == TOTAL SHARES FAILED!!!");
        }
    }

    function invariant_CurrentLiquidityPlusDebtEqualsToNav() public {
        uint256 nav = staking.getNav();
        uint256 liquidity = staking.getLiquidity();

        if (liquidity == 0) {
            return;
        }

        uint256 totalDebt;
        for (uint256 i = 0; i < borrowers.length; i++) {
            uint256 debt = handler.ghost_borrowerDebt(borrowers[i]);
            totalDebt += debt;
        }

        assertEq(liquidity + totalDebt, nav, "Liquidity + debt == nav FAILED!!!");
    }

    function invariant_ClaimedRewardsPlusPendingToClaimEqualsToTotalRewards() public {
        uint256 pending;
        uint256 claimed;
        for (uint256 i = 0; i < suppliers.length; i++) {
            pending += staking.getUserPendingRewards(suppliers[i]) + staking.getUserPendingToClaimRewards(suppliers[i]);
            claimed += handler.ghost_supplierRewardsClaimed(suppliers[i]);
        }

        //assertEq(handler.ghost_totalRewards(), pending + claimed);
        assertApproxEqRel(handler.ghost_totalRewards(), pending + claimed, 1e13);
    }
}
