// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Test} from "forge-std/Test.sol";

import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBSplitHook} from "@bananapus/core-v6/src/interfaces/IJBSplitHook.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBMetadataResolver} from "@bananapus/core-v6/src/libraries/JBMetadataResolver.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";

import {IJBSwapSplitHook} from "../src/interfaces/IJBSwapSplitHook.sol";
import {JBSwapSplitHook} from "../src/JBSwapSplitHook.sol";
import {MockDirectory} from "./mock/MockDirectory.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {MockFeeOnTransferERC20} from "./mock/MockFeeOnTransferERC20.sol";
import {MockReentrantRouterTerminal} from "./mock/MockReentrantRouterTerminal.sol";
import {MockRouterTerminal} from "./mock/MockRouterTerminal.sol";
import {MockTerminal} from "./mock/MockTerminal.sol";

contract JBSwapSplitHookTest is Test {
    uint256 internal constant PROJECT_ID = 2;

    MockDirectory internal directory;
    MockTerminal internal terminal;
    MockRouterTerminal internal router;
    JBSwapSplitHook internal hook;
    MockERC20 internal inputToken;
    MockERC20 internal usdc;

    function setUp() public {
        directory = new MockDirectory();
        terminal = new MockTerminal();
        router = new MockRouterTerminal(directory);
        hook = new JBSwapSplitHook({directory: directory, routerTerminal: router});

        inputToken = new MockERC20("Input", "IN", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        directory.setIsTerminal({projectId: PROJECT_ID, terminal: terminal, flag: true});
        directory.setPrimaryTerminal({projectId: PROJECT_ID, token: address(inputToken), terminal: terminal});
        directory.setPrimaryTerminal({projectId: PROJECT_ID, token: address(usdc), terminal: terminal});
        directory.setPrimaryTerminal({projectId: PROJECT_ID, token: JBConstants.NATIVE_TOKEN, terminal: terminal});

        terminal.setAccountingContext({
            projectId: PROJECT_ID,
            token: address(inputToken),
            decimals: 18,
            currency: uint32(uint160(address(inputToken)))
        });
        terminal.setAccountingContext({
            projectId: PROJECT_ID, token: address(usdc), decimals: 6, currency: uint32(uint160(address(usdc)))
        });
        terminal.setAccountingContext({
            projectId: PROJECT_ID,
            token: JBConstants.NATIVE_TOKEN,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
    }

    function test_processSplitWith_swapsERC20InputIntoBeneficiaryToken() public {
        uint256 amount = 100e18;
        inputToken.mint({to: address(terminal), amount: amount});
        router.setRate({numerator: 2, denominator: 1});

        terminal.executeSplit(_context({tokenIn: address(inputToken), tokenOut: address(usdc), amount: amount}));

        assertEq(terminal.balanceOf(PROJECT_ID, address(usdc)), 200e18, "output added to project balance");
        assertEq(inputToken.balanceOf(address(hook)), 0, "hook holds no input");
        assertEq(inputToken.allowance(address(hook), address(router)), 0, "router allowance cleared");
    }

    function test_processSplitWith_swapsNativeInputIntoBeneficiaryToken() public {
        uint256 amount = 20 ether;
        router.setRate({numerator: 2000e6, denominator: 1 ether});

        terminal.executeSplit{value: amount}(
            _context({tokenIn: JBConstants.NATIVE_TOKEN, tokenOut: address(usdc), amount: amount})
        );

        assertEq(terminal.balanceOf(PROJECT_ID, address(usdc)), 40_000e6, "USDC output added");
        assertEq(address(hook).balance, 0, "hook holds no ETH");
    }

    function test_processSplitWith_canRouteIntoNativeToken() public {
        uint256 amount = 100e18;
        inputToken.mint({to: address(terminal), amount: amount});
        vm.deal({account: address(router), newBalance: 200 ether});
        router.setRate({numerator: 1 ether, denominator: 100e18});

        terminal.executeSplit(
            _context({tokenIn: address(inputToken), tokenOut: JBConstants.NATIVE_TOKEN, amount: amount})
        );

        assertEq(terminal.balanceOf(PROJECT_ID, JBConstants.NATIVE_TOKEN), 1 ether, "native output added");
        assertEq(inputToken.balanceOf(address(hook)), 0, "hook holds no input");
    }

    function test_processSplitWith_returnsERC20ResidueToSourceProject() public {
        uint256 amount = 100e18;
        inputToken.mint({to: address(terminal), amount: amount});
        router.setConsumeBps(6000);
        router.setRate({numerator: 2, denominator: 1});

        terminal.executeSplit(_context({tokenIn: address(inputToken), tokenOut: address(usdc), amount: amount}));

        assertEq(terminal.balanceOf(PROJECT_ID, address(usdc)), 120e18, "output added for consumed input");
        assertEq(terminal.balanceOf(PROJECT_ID, address(inputToken)), 40e18, "residue returned");
        assertEq(inputToken.balanceOf(address(hook)), 0, "hook holds no residue");
    }

    function test_processSplitWith_returnsNativeResidueToSourceProject() public {
        uint256 amount = 10 ether;
        router.setConsumeBps(6000);
        router.setRate({numerator: 1000e6, denominator: 1 ether});

        terminal.executeSplit{value: amount}(
            _context({tokenIn: JBConstants.NATIVE_TOKEN, tokenOut: address(usdc), amount: amount})
        );

        assertEq(terminal.balanceOf(PROJECT_ID, address(usdc)), 6000e6, "output added for consumed ETH");
        assertEq(terminal.balanceOf(PROJECT_ID, JBConstants.NATIVE_TOKEN), 4 ether, "ETH residue returned");
        assertEq(address(hook).balance, 0, "hook holds no ETH");
    }

    function test_processSplitWith_routesActualFeeOnTransferAmount() public {
        MockFeeOnTransferERC20 feeToken = new MockFeeOnTransferERC20("Fee", "FEE", 18, 1000);
        uint256 amount = 100e18;

        feeToken.mint({to: address(terminal), amount: amount});
        directory.setPrimaryTerminal({projectId: PROJECT_ID, token: address(feeToken), terminal: terminal});
        terminal.setAccountingContext({
            projectId: PROJECT_ID, token: address(feeToken), decimals: 18, currency: uint32(uint160(address(feeToken)))
        });

        terminal.executeSplit(_context({tokenIn: address(feeToken), tokenOut: address(usdc), amount: amount}));

        // 10% is skimmed terminal -> hook, then another 10% hook -> router. The router mints output against the
        // amount it actually receives, matching the real router's balance-delta acceptance model.
        assertEq(terminal.balanceOf(PROJECT_ID, address(usdc)), 81e18, "actual received amount routed");
        assertEq(feeToken.balanceOf(address(hook)), 0, "hook holds no fee token");
    }

    function test_processSplitWith_allowsSameTokenNoOpRoute() public {
        uint256 amount = 100e18;
        inputToken.mint({to: address(terminal), amount: amount});

        terminal.executeSplit(_context({tokenIn: address(inputToken), tokenOut: address(inputToken), amount: amount}));

        assertEq(terminal.balanceOf(PROJECT_ID, address(inputToken)), amount, "same token added back");
        assertEq(inputToken.balanceOf(address(hook)), 0, "hook holds no input");
    }

    function test_processSplitWith_revertsForInvalidTerminal() public {
        JBSplitHookContext memory context =
            _context({tokenIn: address(inputToken), tokenOut: address(usdc), amount: 1e18});

        vm.expectRevert(
            abi.encodeWithSelector(IJBSwapSplitHook.JBSwapSplitHook_InvalidTerminal.selector, PROJECT_ID, address(this))
        );
        hook.processSplitWith(context);
    }

    function test_processSplitWith_revertsForWrongGroup() public {
        uint256 amount = 1e18;
        inputToken.mint({to: address(terminal), amount: amount});

        JBSplitHookContext memory context =
            _context({tokenIn: address(inputToken), tokenOut: address(usdc), amount: amount});
        context.groupId = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                IJBSwapSplitHook.JBSwapSplitHook_InvalidGroup.selector,
                address(inputToken),
                1,
                uint256(uint160(address(inputToken)))
            )
        );
        terminal.executeSplit(context);
    }

    function test_processSplitWith_revertsForHookMismatch() public {
        JBSplitHookContext memory context =
            _context({tokenIn: address(inputToken), tokenOut: address(usdc), amount: 1e18});
        context.split.hook = IJBSplitHook(address(0xBEEF));

        vm.prank(address(terminal));
        vm.expectRevert(
            abi.encodeWithSelector(
                IJBSwapSplitHook.JBSwapSplitHook_HookMismatch.selector, address(hook), address(0xBEEF)
            )
        );
        hook.processSplitWith(context);
    }

    function test_processSplitWith_revertsForZeroTokenOut() public {
        uint256 amount = 1e18;
        inputToken.mint({to: address(terminal), amount: amount});

        JBSplitHookContext memory context =
            _context({tokenIn: address(inputToken), tokenOut: address(0), amount: amount});

        vm.expectRevert(IJBSwapSplitHook.JBSwapSplitHook_ZeroTokenOut.selector);
        terminal.executeSplit(context);
    }

    function test_processSplitWith_revertsForNativeAmountMismatch() public {
        uint256 amount = 1 ether;
        JBSplitHookContext memory context =
            _context({tokenIn: JBConstants.NATIVE_TOKEN, tokenOut: address(usdc), amount: amount});

        vm.deal({account: address(terminal), newBalance: amount});
        vm.prank(address(terminal));
        vm.expectRevert(
            abi.encodeWithSelector(IJBSwapSplitHook.JBSwapSplitHook_NativeAmountMismatch.selector, amount, amount - 1)
        );
        hook.processSplitWith{value: amount - 1}(context);
    }

    function test_metadataFor_usesRouterScopedRouteTokenOutKey() public view {
        bytes memory metadata = hook.metadataFor(address(usdc));
        (bool exists, bytes memory data) = JBMetadataResolver.getDataFor({
            id: JBMetadataResolver.getId({purpose: "routeTokenOut", target: address(router)}), metadata: metadata
        });

        assertTrue(exists, "route token exists");
        assertEq(abi.decode(data, (address)), address(usdc), "route token matches");
    }

    function test_supportsInterface() public view {
        assertTrue(hook.supportsInterface(type(IJBSwapSplitHook).interfaceId), "swap split hook");
        assertTrue(hook.supportsInterface(type(IJBSplitHook).interfaceId), "split hook");
        assertTrue(hook.supportsInterface(type(IERC165).interfaceId), "erc165");
        assertFalse(hook.supportsInterface(0xffffffff), "random interface");
    }

    function test_processSplitWith_blocksReentrancyFromRouter() public {
        MockReentrantRouterTerminal reentrantRouter = new MockReentrantRouterTerminal(directory);
        JBSwapSplitHook reentrantHook =
            new JBSwapSplitHook({directory: directory, routerTerminal: IJBTerminal(address(reentrantRouter))});

        directory.setIsTerminal({projectId: PROJECT_ID, terminal: IJBTerminal(address(reentrantRouter)), flag: true});
        reentrantRouter.setReentry({hook_: reentrantHook, projectId_: PROJECT_ID, token_: address(inputToken)});

        uint256 amount = 100e18;
        inputToken.mint({to: address(terminal), amount: amount});

        JBSplitHookContext memory context =
            _contextFor({hook_: reentrantHook, tokenIn: address(inputToken), tokenOut: address(usdc), amount: amount});
        terminal.executeSplit(context);

        assertTrue(reentrantRouter.reentryBlocked(), "nested processSplitWith blocked");
        assertEq(terminal.balanceOf(PROJECT_ID, address(usdc)), amount, "outer route completed");
    }

    function testFuzz_processSplitWith_preservesNoHookResidue(
        uint128 amount,
        uint16 consumeBps,
        uint64 numerator,
        uint64 denominator
    )
        public
    {
        vm.assume(amount > 0);
        consumeBps = uint16(bound(consumeBps, 1, 10_000));
        numerator = uint64(bound(numerator, 1, type(uint32).max));
        denominator = uint64(bound(denominator, 1, type(uint32).max));

        inputToken.mint({to: address(terminal), amount: amount});
        router.setConsumeBps(consumeBps);
        router.setRate({numerator: numerator, denominator: denominator});

        terminal.executeSplit(_context({tokenIn: address(inputToken), tokenOut: address(usdc), amount: amount}));

        uint256 consumed = (uint256(amount) * consumeBps) / 10_000;
        uint256 residue = uint256(amount) - consumed;
        uint256 output = (consumed * numerator) / denominator;

        assertEq(terminal.balanceOf(PROJECT_ID, address(inputToken)), residue, "all residue returned");
        assertEq(terminal.balanceOf(PROJECT_ID, address(usdc)), output, "output recorded");
        assertEq(inputToken.balanceOf(address(hook)), 0, "no hook residue");
        assertEq(usdc.balanceOf(address(hook)), 0, "no hook output");
        assertEq(inputToken.allowance(address(hook), address(router)), 0, "router allowance cleared");
        assertEq(inputToken.allowance(address(hook), address(terminal)), 0, "terminal allowance cleared");
    }

    function _context(
        address tokenIn,
        address tokenOut,
        uint256 amount
    )
        internal
        view
        returns (JBSplitHookContext memory)
    {
        return _contextFor({hook_: hook, tokenIn: tokenIn, tokenOut: tokenOut, amount: amount});
    }

    function _contextFor(
        IJBSplitHook hook_,
        address tokenIn,
        address tokenOut,
        uint256 amount
    )
        internal
        pure
        returns (JBSplitHookContext memory)
    {
        JBSplit memory split = JBSplit({
            percent: 1_000_000_000,
            projectId: 0,
            beneficiary: payable(tokenOut),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: hook_
        });

        return JBSplitHookContext({
            token: tokenIn,
            amount: amount,
            decimals: 18,
            projectId: PROJECT_ID,
            groupId: uint256(uint160(tokenIn)),
            split: split
        });
    }
}
