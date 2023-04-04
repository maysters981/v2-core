//SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "../../src/modules/CollateralModule.sol";
import "../test-utils/MockCoreStorage.sol";

contract EnhancedCollateralModule is CollateralModule, CoreState {
    function enableDepositing(address tokenAddress) public {
        CollateralConfiguration.Data memory config = CollateralConfiguration.load(tokenAddress);
        CollateralConfiguration.set(
            CollateralConfiguration.Data({
                depositingEnabled: true, liquidationBooster: config.liquidationBooster, tokenAddress: tokenAddress, cap: config.cap
            })
        );
    }
 }

contract CollateralModuleTest is Test {
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;

    event Deposited(
        uint128 indexed accountId, 
        address indexed collateralType, 
        uint256 tokenAmount, 
        uint256 liquidationBoosterDeposit, 
        address indexed sender
    );
    event Withdrawn(uint128 indexed accountId, address indexed collateralType, uint256 tokenAmount, address indexed sender);

    EnhancedCollateralModule internal collateralModule;

    function setUp() public {
        collateralModule = new EnhancedCollateralModule();
    }

    function test_GetAccountCollateralBalance() public {
        assertEq(collateralModule.getAccountCollateralBalance(100, Constants.TOKEN_0), Constants.DEFAULT_TOKEN_0_BALANCE);
    }

    function test_GetAccountCollateralBalance_NoSettlementToken() public {
        assertEq(collateralModule.getAccountCollateralBalance(100, Constants.TOKEN_1), Constants.DEFAULT_TOKEN_1_BALANCE);
    }

    function test_GetTotalAccountValue() public {
        int256 uPnL = 100e18;
        assertEq(collateralModule.getTotalAccountValue(100, Constants.TOKEN_0), Constants.DEFAULT_TOKEN_0_BALANCE.toInt() - uPnL);
    }

    function test_GetAccountCollateralBalanceAvailable() public {
        uint256 uPnL = 100e18;
        uint256 im = 1800e18;

        assertEq(
            collateralModule.getAccountCollateralBalanceAvailable(100, Constants.TOKEN_0),
            Constants.DEFAULT_TOKEN_0_BALANCE - uPnL - im
        );
    }

    function test_GetAccountCollateralBalanceAvailable_NoSettlementToken() public {
        assertEq(collateralModule.getAccountCollateralBalanceAvailable(100, Constants.TOKEN_1), Constants.DEFAULT_TOKEN_1_BALANCE);
    }

    function test_GetAccountCollateralBalanceAvailable_OtherToken() public {
        assertEq(collateralModule.getAccountCollateralBalanceAvailable(100, Constants.TOKEN_UNKNOWN), 0);
    }

    function testFuzz_Deposit(address depositor) public {
        // Amount to deposit
        uint256 amount = 500e18;

        // Mock ERC20 external calls
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.balanceOf.selector, collateralModule), abi.encode(0)
        );

        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.allowance.selector, depositor, collateralModule), abi.encode(amount)
        );

        vm.mockCall(
            Constants.TOKEN_0,
            abi.encodeWithSelector(IERC20.transferFrom.selector, depositor, collateralModule, amount),
            abi.encode()
        );

        // Route the deposit from depositor
        vm.prank(depositor);

        // Expect Deposited event
        vm.expectEmit(true, true, true, true, address(collateralModule));
        emit Deposited(100, Constants.TOKEN_0, amount, 0, depositor);

        // Deposit
        collateralModule.deposit(100, Constants.TOKEN_0, amount);

        // Check the collateral balance post deposit
        assertEq(collateralModule.getAccountCollateralBalance(100, Constants.TOKEN_0), Constants.DEFAULT_TOKEN_0_BALANCE + amount);
    }

    function testFuzz_revertWhen_Deposit_WithNotEnoughAllowance(address depositor) public {
        // Amount to deposit
        uint256 amount = 500e18;

        // Mock ERC20 external calls
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.allowance.selector, depositor, collateralModule), abi.encode(0)
        );

        // Route the deposit from depositor
        vm.prank(depositor);

        // Expect revert due to insufficient allowance
        vm.expectRevert(abi.encodeWithSelector(IERC20.InsufficientAllowance.selector, amount, 0));
        collateralModule.deposit(100, Constants.TOKEN_0, amount);
    }

    function testFuzz_revertWhen_Deposit_WithCollateralTypeNotEnabled(address depositor) public {
        // Amount to deposit
        uint256 amount = 500e18;

        // Route the deposit from depositor
        vm.prank(depositor);

        // Expect revert due to unsupported collateral type
        vm.expectRevert(abi.encodeWithSelector(CollateralConfiguration.CollateralDepositDisabled.selector, Constants.TOKEN_1));
        collateralModule.deposit(100, Constants.TOKEN_1, amount);
    }

    function test_Withdraw() public {
        // Amount to withdraw
        uint256 amount = 500e18;

        // Mock ERC20 external calls
        vm.mockCall(Constants.TOKEN_0, abi.encodeWithSelector(IERC20.transfer.selector, Constants.ALICE, amount), abi.encode());

        // Route the deposit from Alice
        vm.prank(Constants.ALICE);

        // Expect Withdrawn event
        vm.expectEmit(true, true, true, true, address(collateralModule));
        emit Withdrawn(100, Constants.TOKEN_0, amount, Constants.ALICE);

        // Withdraw
        collateralModule.withdraw(100, Constants.TOKEN_0, amount);

        // Check the collateral balance post withdraw
        assertEq(collateralModule.getAccountCollateralBalance(100, Constants.TOKEN_0), Constants.DEFAULT_TOKEN_0_BALANCE - amount);
    }

    function test_revertWhen_Withdraw_UnautohorizedAccount(address otherAddress) public {
        vm.assume(otherAddress != Constants.ALICE);

        // Amount to withdraw
        uint256 amount = 500e18;

        // Route the deposit from other address
        vm.prank(otherAddress);

        // Expect revert due to unauthorized account
        vm.expectRevert(abi.encodeWithSelector(Account.PermissionDenied.selector, 100, otherAddress));
        collateralModule.withdraw(100, Constants.TOKEN_0, amount);
    }

    function test_revertWhen_Withdraw_MoreThanBalance() public {
        // Amount to withdraw
        uint256 amount = 10500e18;

        // Route the deposit from Alice
        vm.prank(Constants.ALICE);

        // Expect revert due to insufficient collateral balance
        vm.expectRevert(abi.encodeWithSelector(Collateral.InsufficientLiquidationBoosterBalance.selector, 500e18));
        collateralModule.withdraw(100, Constants.TOKEN_0, amount);
    }

    function test_revertWhen_Withdraw_WhenIMNoLongerSatisfied() public {
        // Amount to withdraw
        uint256 amount = 9500e18;

        // Route the deposit from Alice
        vm.prank(Constants.ALICE);

        // Expect revert due to insufficient margin coverage
        vm.expectRevert(abi.encodeWithSelector(Account.AccountBelowIM.selector, 100));
        collateralModule.withdraw(100, Constants.TOKEN_0, amount);
    }

    function test_revertWhen_CapExceeded_Deposit() public {
        address depositor = address(1);
        uint256 amount = Constants.TOKEN_0_CAP + 1;

        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.balanceOf.selector, collateralModule), abi.encode(0)
        );
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.allowance.selector, depositor, collateralModule), abi.encode(amount)
        );
        vm.mockCall(
            Constants.TOKEN_0,
            abi.encodeWithSelector(IERC20.transferFrom.selector, depositor, collateralModule, amount),
            abi.encode()
        );        
        vm.prank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralModule.CollateralCapExceeded.selector, Constants.TOKEN_0, Constants.TOKEN_0_CAP, 0, amount, 0
            )
        );
        collateralModule.deposit(100, Constants.TOKEN_0, amount);
    }

    function test_revertWhen_CapExceeded_MultipleDeposits() public {
        address depositor = address(1);
        uint256 amount = Constants.TOKEN_0_CAP / 2;

        // First Deposit
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.balanceOf.selector, collateralModule), abi.encode(0)
        );
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.allowance.selector, depositor, collateralModule), abi.encode(amount)
        );
        vm.mockCall(
            Constants.TOKEN_0,
            abi.encodeWithSelector(IERC20.transferFrom.selector, depositor, collateralModule, amount),
            abi.encode()
        );        
        vm.prank(depositor);
        vm.expectEmit(true, true, true, true, address(collateralModule));
        emit Deposited(100, Constants.TOKEN_0, amount, 0, depositor);
        collateralModule.deposit(100, Constants.TOKEN_0, amount);

        // Second Deposit
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.balanceOf.selector, collateralModule), abi.encode(amount)
        );
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.allowance.selector, depositor, collateralModule), abi.encode(amount+1)
        );
        vm.mockCall(
            Constants.TOKEN_0,
            abi.encodeWithSelector(IERC20.transferFrom.selector, depositor, collateralModule, amount+1),
            abi.encode()
        );        
        vm.prank(depositor);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollateralModule.CollateralCapExceeded.selector, Constants.TOKEN_0, Constants.TOKEN_0_CAP, amount, amount + 1, 0
            )
        );
        collateralModule.deposit(100, Constants.TOKEN_0, amount + 1);
    }

    function test_Deposit_DifferentCaps() public {
        address depositor = address(1);

        // Deposit Token 0
        uint256 amount = Constants.TOKEN_0_CAP;
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.balanceOf.selector, collateralModule), abi.encode(0)
        );
        vm.mockCall(
            Constants.TOKEN_0, abi.encodeWithSelector(IERC20.allowance.selector, depositor, collateralModule), abi.encode(amount)
        );
        vm.mockCall(
            Constants.TOKEN_0,
            abi.encodeWithSelector(IERC20.transferFrom.selector, depositor, collateralModule, amount),
            abi.encode()
        );

        vm.prank(depositor);
        vm.expectEmit(true, true, true, true, address(collateralModule));
        emit Deposited(100, Constants.TOKEN_0, amount, 0, depositor);
        collateralModule.deposit(100, Constants.TOKEN_0, amount);

        assertEq(collateralModule.getAccountCollateralBalance(100, Constants.TOKEN_0), Constants.DEFAULT_TOKEN_0_BALANCE + amount);

        // Deposit Token 1
        collateralModule.enableDepositing(Constants.TOKEN_1);
        amount = Constants.TOKEN_1_CAP;
        vm.mockCall(
            Constants.TOKEN_1, abi.encodeWithSelector(IERC20.balanceOf.selector, collateralModule), abi.encode(0)
        );
        vm.mockCall(
            Constants.TOKEN_1, abi.encodeWithSelector(IERC20.allowance.selector, depositor, collateralModule), abi.encode(amount)
        );
        vm.mockCall(
            Constants.TOKEN_1,
            abi.encodeWithSelector(IERC20.transferFrom.selector, depositor, collateralModule, amount),
            abi.encode()
        );

        vm.prank(depositor);
        vm.expectEmit(true, true, true, true, address(collateralModule));
        emit Deposited(100, Constants.TOKEN_1, amount, 0, depositor);
        collateralModule.deposit(100, Constants.TOKEN_1, amount);

        assertEq(collateralModule.getAccountCollateralBalance(100, Constants.TOKEN_1), Constants.DEFAULT_TOKEN_1_BALANCE + amount);
    }
}
