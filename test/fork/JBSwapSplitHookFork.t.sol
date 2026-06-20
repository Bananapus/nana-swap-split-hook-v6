// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {IJBDirectory} from "@bananapus/core-v6/src/interfaces/IJBDirectory.sol";
import {IJBTerminal} from "@bananapus/core-v6/src/interfaces/IJBTerminal.sol";
import {IJBTokens} from "@bananapus/core-v6/src/interfaces/IJBTokens.sol";
import {JBConstants} from "@bananapus/core-v6/src/libraries/JBConstants.sol";
import {JBSplit} from "@bananapus/core-v6/src/structs/JBSplit.sol";
import {JBSplitHookContext} from "@bananapus/core-v6/src/structs/JBSplitHookContext.sol";
import {JBRouterTerminal} from "@bananapus/router-terminal-v6/src/JBRouterTerminal.sol";
import {IWETH9} from "@bananapus/router-terminal-v6/src/interfaces/IWETH9.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {JBSwapSplitHook} from "../../src/JBSwapSplitHook.sol";
import {MockDirectory} from "../mock/MockDirectory.sol";
import {MockJBTokens} from "../mock/MockJBTokens.sol";
import {MockTerminal} from "../mock/MockTerminal.sol";

contract JBSwapSplitHookForkTest is Test {
    uint256 internal constant PROJECT_ID = 2;

    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant V4_POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    MockDirectory internal directory;
    MockTerminal internal terminal;
    JBRouterTerminal internal router;
    JBSwapSplitHook internal hook;

    function setUp() public {
        string memory rpc = vm.envOr("RPC_ETHEREUM_MAINNET", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);

        vm.createSelectFork(rpc);

        directory = new MockDirectory();
        terminal = new MockTerminal();

        MockJBTokens tokens = new MockJBTokens();
        router = new JBRouterTerminal({
            directory: IJBDirectory(address(directory)),
            tokens: IJBTokens(address(tokens)),
            permit2: IPermit2(PERMIT2),
            buybackHook: address(0),
            trustedForwarder: address(0),
            deployer: address(this)
        });
        router.setChainSpecificConstants({
            newWrappedNativeToken: IWETH9(MAINNET_WETH),
            newFactory: IUniswapV3Factory(V3_FACTORY),
            newPoolManager: IPoolManager(V4_POOL_MANAGER),
            newUniv4Hook: address(0)
        });

        hook = new JBSwapSplitHook({directory: directory, routerTerminal: IJBTerminal(address(router))});

        directory.setIsTerminal({projectId: PROJECT_ID, terminal: terminal, flag: true});
        directory.setPrimaryTerminal({projectId: PROJECT_ID, token: MAINNET_USDC, terminal: terminal});
        directory.setPrimaryTerminal({projectId: PROJECT_ID, token: MAINNET_WETH, terminal: terminal});
        directory.setPrimaryTerminal({projectId: PROJECT_ID, token: JBConstants.NATIVE_TOKEN, terminal: terminal});

        terminal.setAccountingContext({
            projectId: PROJECT_ID, token: MAINNET_USDC, decimals: 6, currency: uint32(uint160(MAINNET_USDC))
        });
        terminal.setAccountingContext({
            projectId: PROJECT_ID, token: MAINNET_WETH, decimals: 18, currency: uint32(uint160(MAINNET_WETH))
        });
        terminal.setAccountingContext({
            projectId: PROJECT_ID,
            token: JBConstants.NATIVE_TOKEN,
            decimals: 18,
            currency: uint32(uint160(JBConstants.NATIVE_TOKEN))
        });
    }

    function testFork_nativeEthSplitSwapsIntoMainnetUsdcThroughRealRouter() public {
        uint256 amount = 0.01 ether;

        terminal.executeSplit{value: amount}(
            _context({tokenIn: JBConstants.NATIVE_TOKEN, tokenOut: MAINNET_USDC, amount: amount})
        );

        assertGt(terminal.balanceOf(PROJECT_ID, MAINNET_USDC), 0, "USDC added");
        assertEq(address(hook).balance, 0, "hook has no ETH");
        assertEq(IERC20(MAINNET_USDC).balanceOf(address(hook)), 0, "hook has no USDC");
    }

    function testFork_mainnetUsdcSplitSwapsIntoNativeEthThroughRealRouter() public {
        uint256 amount = 100e6;
        deal({token: MAINNET_USDC, to: address(terminal), give: amount});

        terminal.executeSplit(_context({tokenIn: MAINNET_USDC, tokenOut: JBConstants.NATIVE_TOKEN, amount: amount}));

        assertGt(terminal.balanceOf(PROJECT_ID, JBConstants.NATIVE_TOKEN), 0, "ETH added");
        assertEq(IERC20(MAINNET_USDC).balanceOf(address(hook)), 0, "hook has no USDC");
        assertEq(address(hook).balance, 0, "hook has no ETH");
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
        JBSplit memory split = JBSplit({
            percent: 1_000_000_000,
            projectId: 0,
            beneficiary: payable(tokenOut),
            preferAddToBalance: false,
            lockedUntil: 0,
            hook: hook
        });

        return JBSplitHookContext({
            token: tokenIn,
            amount: amount,
            decimals: tokenIn == MAINNET_USDC ? 6 : 18,
            projectId: PROJECT_ID,
            groupId: uint256(uint160(tokenIn)),
            split: split
        });
    }
}
