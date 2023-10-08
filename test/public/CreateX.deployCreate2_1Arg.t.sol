// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {BaseTest} from "../utils/BaseTest.sol";
import {ERC20MockPayable} from "../mocks/ERC20MockPayable.sol";
import {CreateX} from "../../src/CreateX.sol";

contract CreateX_DeployCreate2_1Arg_Public_Test is BaseTest {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER VARIABLES                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    address internal immutable SELF = address(this);

    string internal arg1;
    string internal arg2;
    address internal arg3;
    uint256 internal arg4;
    bytes internal args;

    bytes internal cachedInitCode;
    bytes32 internal initCodeHash;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HELPER FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Indicates whether a permissioned deploy protection and/or a cross-chain redeploy protection
     * has been configured via `salt` or whether it must revert.
     * @param originalDeployer The 20-byte original deployer address.
     * @param salt The 32-byte random value used to create the contract address.
     * @return permissionedDeployProtection The Boolean variable that specifies whether a permissioned redeploy
     * protection has been configured.
     * @return xChainRedeployProtection The Boolean variable that specifies whether a cross-chain deploy
     * protection has been configured.
     * @return mustRevert The Boolean variable that specifies whether it must revert.
     * @return guardedSalt The guarded 32-byte random value used to create the contract address.
     */
    function parseFuzzerSalt(
        address originalDeployer,
        bytes32 salt
    )
        internal
        returns (bool permissionedDeployProtection, bool xChainRedeployProtection, bool mustRevert, bytes32 guardedSalt)
    {
        vm.startPrank(originalDeployer);
        (CreateX.SenderBytes senderBytes, CreateX.RedeployProtectionFlag redeployProtectionFlag) = createXHarness
            .exposed_parseSalt(salt);
        vm.stopPrank();

        if (
            senderBytes == CreateX.SenderBytes.MsgSender &&
            redeployProtectionFlag == CreateX.RedeployProtectionFlag.True
        ) {
            vm.startPrank(originalDeployer);
            // Configures a permissioned deploy protection as well as a cross-chain redeploy protection.
            guardedSalt = createXHarness.exposed_guard(salt);
            vm.stopPrank();
            permissionedDeployProtection = true;
            xChainRedeployProtection = true;
        } else if (
            senderBytes == CreateX.SenderBytes.MsgSender &&
            redeployProtectionFlag == CreateX.RedeployProtectionFlag.False
        ) {
            vm.startPrank(originalDeployer);
            // Configures solely a permissioned deploy protection.
            guardedSalt = createXHarness.exposed_guard(salt);
            vm.stopPrank();
            permissionedDeployProtection = true;
        } else if (senderBytes == CreateX.SenderBytes.MsgSender) {
            // Reverts if the 21st byte is greater than `0x01` in order to enforce developer explicitness.
            mustRevert = true;
        } else if (
            senderBytes == CreateX.SenderBytes.ZeroAddress &&
            redeployProtectionFlag == CreateX.RedeployProtectionFlag.True
        ) {
            vm.startPrank(originalDeployer);
            // Configures solely a cross-chain redeploy protection.
            guardedSalt = createXHarness.exposed_guard(salt);
            vm.stopPrank();
            xChainRedeployProtection = true;
        } else if (
            senderBytes == CreateX.SenderBytes.ZeroAddress &&
            redeployProtectionFlag == CreateX.RedeployProtectionFlag.Unspecified
        ) {
            // Reverts if the 21st byte is greater than `0x01` in order to enforce developer explicitness.
            mustRevert = true;
        } else {
            // In all other cases, the salt value `salt` is not modified.
            guardedSalt = salt;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Solidity version `0.8.21` raises an ICE (Internal Compiler Error)
    // when an event is emitted from another contract: https://github.com/ethereum/solidity/issues/14430.

    /**
     * @dev Event that is emitted when `amount` ERC-20 tokens are moved from one
     * account (`owner`) to another (`to`).
     * @param owner The 20-byte owner address.
     * @param to The 20-byte receiver address.
     * @param amount The 32-byte token amount to be transferred.
     */
    event Transfer(address indexed owner, address indexed to, uint256 amount);

    /**
     * @dev Event that is emitted when a contract is successfully created.
     * @param newContract The address of the new contract.
     */
    event ContractCreation(address indexed newContract);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Error that occurs when the contract creation code has zero-byte length.
     * @param emitter The contract that emits the error.
     */
    error ZeroByteInitCode(address emitter);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            TESTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setUp() public override {
        BaseTest.setUp();
        arg1 = "MyToken";
        arg2 = "MTKN";
        arg3 = makeAddr("initialAccount");
        arg4 = 100;
        args = abi.encode(arg1, arg2, arg3, arg4);
        cachedInitCode = abi.encodePacked(type(ERC20MockPayable).creationCode, args);
        initCodeHash = keccak256(cachedInitCode);
    }

    modifier whenTheInitCodeSuccessfullyCreatesARuntimeBytecodeWithANonZeroLength() {
        if (cachedInitCode.length == 0) {
            revert ZeroByteInitCode(SELF);
        }
        _;
    }

    function testFuzz_whenTheInitCodeSuccessfullyCreatesARuntimeBytecodeWithANonZeroLength(
        address originalDeployer,
        uint256 msgValue,
        uint64 chainId,
        address msgSender
    ) external whenTheInitCodeSuccessfullyCreatesARuntimeBytecodeWithANonZeroLength {
        msgValue = bound(msgValue, 0, type(uint64).max);
        vm.deal(originalDeployer, 2 * msgValue);
        vm.assume(
            chainId != block.chainid &&
                chainId != 0 &&
                originalDeployer != msgSender &&
                originalDeployer != zeroAddress &&
                msgSender != zeroAddress
        );

        vm.startPrank(originalDeployer);
        bytes32 salt = createXHarness.exposed_generateSalt();
        vm.stopPrank();
        (
            bool permissionedDeployProtection,
            bool xChainRedeployProtection,
            bool mustRevert,
            bytes32 guardedSalt
        ) = parseFuzzerSalt(originalDeployer, salt);
        // When we pseudo-randomly calculate the salt value `salt`, we must never have configured a permissioned
        // deploy protection or a cross-chain redeploy protection, and it must never revert.
        assertTrue(!permissionedDeployProtection && !xChainRedeployProtection && !mustRevert);

        // We calculate the address beforehand where the contract is to be deployed.
        address computedAddress = createX.computeCreate2Address(guardedSalt, initCodeHash, createXAddr);

        // We also check for the ERC-20 standard `Transfer` event.
        vm.expectEmit(true, true, true, true, computedAddress);
        emit Transfer(zeroAddress, arg3, arg4);
        // It returns a contract address with a non-zero bytecode length and a potential non-zero ether balance.
        // It emits the event `ContractCreation` with the contract address as indexed argument.
        vm.expectEmit(true, true, true, true, createXAddr);
        emit ContractCreation(computedAddress);
        vm.startPrank(originalDeployer);
        address newContract = createX.deployCreate2{value: msgValue}(cachedInitCode);
        vm.stopPrank();

        assertEq(newContract, computedAddress);
        assertNotEq(newContract, zeroAddress);
        assertNotEq(newContract.code.length, 0);
        assertEq(newContract.balance, msgValue);
        assertEq(createXAddr.balance, 0);
        assertEq(ERC20MockPayable(computedAddress).name(), arg1);
        assertEq(ERC20MockPayable(computedAddress).symbol(), arg2);
        assertEq(ERC20MockPayable(computedAddress).balanceOf(arg3), arg4);

        vm.chainId(chainId);
        // We mock a potential frontrunner address.
        vm.deal(msgSender, msgValue);
        vm.startPrank(msgSender);
        address newContractMsgSender = createX.deployCreate2{value: msgValue}(cachedInitCode);
        vm.stopPrank();

        // The newly created contract on chain `chainId` must not be the same as the previously created
        // contract at the `computedAddress` address.
        assertNotEq(newContractMsgSender, computedAddress);
        assertNotEq(newContractMsgSender, zeroAddress);
        assertNotEq(newContractMsgSender.code.length, 0);
        assertEq(newContractMsgSender.balance, msgValue);
        assertEq(createXAddr.balance, 0);
        assertEq(ERC20MockPayable(newContractMsgSender).name(), arg1);
        assertEq(ERC20MockPayable(newContractMsgSender).symbol(), arg2);
        assertEq(ERC20MockPayable(newContractMsgSender).balanceOf(arg3), arg4);

        // We mock the original caller.
        vm.startPrank(originalDeployer);
        address newContractOriginalDeployer = createX.deployCreate2{value: msgValue}(cachedInitCode);
        vm.stopPrank();
        // The newly created contract on chain `chainId` must not be the same as the previously created
        // contract at the `computedAddress` address as well as at the `newContractMsgSender` address.
        assertNotEq(newContractOriginalDeployer, computedAddress);
        assertNotEq(newContractOriginalDeployer, newContractMsgSender);
        assertNotEq(newContractOriginalDeployer, zeroAddress);
        assertNotEq(newContractOriginalDeployer.code.length, 0);
        assertEq(newContractOriginalDeployer.balance, msgValue);
        assertEq(createXAddr.balance, 0);
        assertEq(ERC20MockPayable(newContractOriginalDeployer).name(), arg1);
        assertEq(ERC20MockPayable(newContractOriginalDeployer).symbol(), arg2);
        assertEq(ERC20MockPayable(newContractOriginalDeployer).balanceOf(arg3), arg4);
    }

    modifier whenTheInitCodeSuccessfullyCreatesARuntimeBytecodeWithAZeroLength() {
        _;
    }

    function testFuzz_WhenTheInitCodeSuccessfullyCreatesARuntimeBytecodeWithAZeroLength(
        address originalDeployer,
        uint256 msgValue
    ) external whenTheInitCodeSuccessfullyCreatesARuntimeBytecodeWithAZeroLength {
        msgValue = bound(msgValue, 0, type(uint64).max);
        vm.deal(originalDeployer, msgValue);
        vm.assume(originalDeployer != zeroAddress);
        vm.startPrank(originalDeployer);
        bytes32 salt = createXHarness.exposed_generateSalt();
        vm.stopPrank();
        (bool permissionedDeployProtection, bool xChainRedeployProtection, bool mustRevert, ) = parseFuzzerSalt(
            originalDeployer,
            salt
        );
        // When we pseudo-randomly calculate the salt value `salt`, we must never have configured a permissioned
        // deploy protection or a cross-chain redeploy protection, and it must never revert.
        assertTrue(!permissionedDeployProtection && !xChainRedeployProtection && !mustRevert);
        vm.startPrank(originalDeployer);
        // It should revert.
        bytes memory expectedErr = abi.encodeWithSelector(CreateX.FailedContractCreation.selector, createXAddr);
        vm.expectRevert(expectedErr);
        createX.deployCreate2{value: msgValue}(new bytes(0));
        vm.stopPrank();
    }

    modifier whenTheInitCodeFailsToDeployARuntimeBytecode() {
        _;
    }

    function testFuzz_WhenTheInitCodeFailsToDeployARuntimeBytecode(
        address originalDeployer,
        uint256 msgValue
    ) external whenTheInitCodeFailsToDeployARuntimeBytecode {
        msgValue = bound(msgValue, 0, type(uint64).max);
        vm.deal(originalDeployer, msgValue);
        vm.assume(originalDeployer != zeroAddress);
        vm.startPrank(originalDeployer);
        bytes32 salt = createXHarness.exposed_generateSalt();
        vm.stopPrank();
        (bool permissionedDeployProtection, bool xChainRedeployProtection, bool mustRevert, ) = parseFuzzerSalt(
            originalDeployer,
            salt
        );
        // When we pseudo-randomly calculate the salt value `salt`, we must never have configured a permissioned
        // deploy protection or a cross-chain redeploy protection, and it must never revert.
        assertTrue(!permissionedDeployProtection && !xChainRedeployProtection && !mustRevert);
        // The following contract creation code contains the invalid opcode `PUSH0` (`0x5F`) and `CREATE` must therefore
        // return the zero address (technically zero bytes `0x`), as the deployment fails. This test also ensures that if
        // we ever accidentally change the EVM version in Foundry and Hardhat, we will always have a corresponding failed test.
        bytes memory invalidInitCode = bytes("0x5f8060093d393df3");
        vm.startPrank(originalDeployer);
        // It should revert.
        bytes memory expectedErr = abi.encodeWithSelector(CreateX.FailedContractCreation.selector, createXAddr);
        vm.expectRevert(expectedErr);
        createX.deployCreate2{value: msgValue}(invalidInitCode);
        vm.stopPrank();
    }
}
