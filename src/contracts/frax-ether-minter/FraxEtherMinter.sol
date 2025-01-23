// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.23;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ========================== frxETHMinter_V2 =========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Reviewer(s) / Contributor(s)
// Travis Moore: https://github.com/FortisFortuna
// Drake Evans: https://github.com/DrakeEvans
// Dennis: https://github.com/denett

import { PublicReentrancyGuard } from "frax-std/access-control/v2/PublicReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILendingPool } from "src/contracts/lending-pool/interfaces/ILendingPool.sol";
import { EtherRouterRole } from "../access-control/EtherRouterRole.sol";
import { Timelock2Step } from "frax-std/access-control/v2/Timelock2Step.sol";
import { OperatorRole } from "frax-std/access-control/v2/OperatorRole.sol";
import { IFrxEth } from "../interfaces/IFrxEth.sol";
import { ISfrxEth } from "../interfaces/ISfrxEth.sol";

/// @notice Used for the constructor
/// @param frxEthErc20Address Address for frxETH
/// @param sfrxEthErc20Address Address for sfrxETH
/// @param timelockAddress Address of the governance timelock
/// @param etherRouterAddress Address of the Ether Router
/// @param operatorRoleAddress Address of the operator
struct FraxEtherMinterParams {
    address frxEthErc20Address;
    address sfrxEthErc20Address;
    address payable timelockAddress;
    address payable etherRouterAddress;
    address operatorRoleAddress;
}

/// @title Authorized minter contract for frxETH
/// @notice Accepts user-supplied ETH and converts it to frxETH (submit()), and also optionally inline stakes it for sfrxETH (submitAndDeposit())
/**
 * @dev Has permission to mint frxETH.
 *     Once +32 ETH has accumulated, adds it to a validator, which then deposits it for ETH 2.0 staking (depositEther())
 *     Withhold ratio refers to what percentage of ETH this contract keeps whenever a user makes a deposit. 0% is kept initially
 */
contract FraxEtherMinter is EtherRouterRole, OperatorRole, Timelock2Step, PublicReentrancyGuard {
    // ==============================================================================
    // Storage & Constructor
    // ==============================================================================

    /// @notice frxETH
    IFrxEth public immutable frxEthToken;
    ISfrxEth public immutable sfrxEthToken;

    /// @notice If minting frxETH is paused
    bool public mintFrxEthPaused;

    /// @notice Constructor
    /// @param _params The FraxEtherMinterParams
    constructor(
        FraxEtherMinterParams memory _params
    )
        Timelock2Step(_params.timelockAddress)
        EtherRouterRole(_params.etherRouterAddress)
        OperatorRole(_params.operatorRoleAddress)
    {
        frxEthToken = IFrxEth(_params.frxEthErc20Address);
        sfrxEthToken = ISfrxEth(_params.sfrxEthErc20Address);
    }

    /// @notice Fallback to minting frxETH to the sender
    receive() external payable {
        _submit(msg.sender);
    }

    // ==============================================================================
    // Acccess Control Functions
    // ==============================================================================

    /// @notice Make sure the sender is either the operator or the timelock
    function _requireSenderIsOperatorOrTimelock() internal view {
        if (!(_isTimelock(msg.sender) || _isOperator(msg.sender))) {
            revert NotOperatorOrTimelock();
        }
    }

    // ==============================================================================
    // Main Functions
    // ==============================================================================

    /// @notice Mints frxETH to the sender based on the ETH value sent
    function mintFrxEth() external payable {
        // Give the frxETH to the sender after it is generated
        _submit(msg.sender);
    }

    /// @notice Mints frxETH to the designated recipient based on the ETH value sent
    /// @param _recipient Destination for the minted frxETH
    function mintFrxEthAndGive(address _recipient) external payable {
        // Give the frxETH to this contract after it is generated
        _submit(_recipient);
    }

    /// @notice Mint frxETH to the recipient using sender's funds. Internal portion
    /// @param _recipient Destination for the minted frxETH
    function _submit(address _recipient) internal nonReentrant {
        // Initial pause and value checks
        if (mintFrxEthPaused) revert MintFrxEthIsPaused();
        if (msg.value == 0) revert CannotMintZero();

        // Deposit Ether to the Ether Router
        etherRouter.depositEther{ value: msg.value }();

        // Give the sender frxETH
        frxEthToken.minter_mint(_recipient, msg.value);

        // Accrue interest (will also update the utilization rate)
        ILendingPool(address(etherRouter.lendingPool())).addInterest(false);

        emit EthSubmitted(msg.sender, _recipient, msg.value);
    }

    /// @notice Mint frxETH and deposit it to receive sfrxETH in one transaction
    /// @param _recipient Destination for the minted frxETH
    /// @return _shares Output amount of sfrxETH
    function submitAndDeposit(address _recipient) external payable returns (uint256 _shares) {
        // Give the frxETH to this contract after it is generated
        _submit(address(this));

        // Approve frxETH to sfrxETH for staking
        frxEthToken.approve(address(sfrxEthToken), msg.value);

        // Deposit the frxETH and give the generated sfrxETH to the final recipient
        _shares = sfrxEthToken.deposit(msg.value, _recipient);
        if (_shares == 0) revert NoSfrxEthReturned();
    }

    /// @notice Toggle allowing submits
    function togglePauseSubmits() external {
        _requireSenderIsOperatorOrTimelock();
        mintFrxEthPaused = !mintFrxEthPaused;

        emit MintFrxEthPaused(mintFrxEthPaused);
    }

    // ==============================================================================
    // Restricted Functions
    // ==============================================================================

    /// @notice Change the Ether Router address
    /// @param _newEtherRouterAddress Ether Router address
    function setEtherRouterAddress(address payable _newEtherRouterAddress) external {
        _requireSenderIsTimelock();
        _setEtherRouter(_newEtherRouterAddress);
    }

    /// @notice Change the Operator address
    /// @param _newOperatorAddress Operator address
    function setOperatorAddress(address _newOperatorAddress) external {
        _requireSenderIsTimelock();
        _setOperator(_newOperatorAddress);
    }

    // ==============================================================================
    // Recovery Functions
    // ==============================================================================

    /// @notice For emergencies if something gets stuck
    /// @param _amount Amount of ETH to recover
    function recoverEther(uint256 _amount) external {
        _requireSenderIsOperatorOrTimelock();

        (bool _success, ) = address(msg.sender).call{ value: _amount }("");
        if (!_success) revert InvalidEthTransfer();

        emit EmergencyEtherRecovered(_amount);
    }

    /// @notice For emergencies if someone accidentally sent some ERC20 tokens here
    /// @param _tokenAddress Address of the ERC20 to recover
    /// @param _tokenAmount Amount of the ERC20 to recover
    function recoverErc20(address _tokenAddress, uint256 _tokenAmount) external {
        _requireSenderIsOperatorOrTimelock();
        require(IERC20(_tokenAddress).transfer(msg.sender, _tokenAmount), "recoverErc20: Transfer failed");

        emit EmergencyErc20Recovered(_tokenAddress, _tokenAmount);
    }

    // ==============================================================================
    // Errors
    // ==============================================================================

    /// @notice Cannot mint 0
    error CannotMintZero();

    /// @notice Invalid ETH transfer during recoverEther
    error InvalidEthTransfer();

    /// @notice mintFrxEth is paused
    error MintFrxEthIsPaused();

    /// @notice When no sfrxETH is generated from submitAndDeposit
    error NoSfrxEthReturned();

    /// @notice Not Operator or timelock
    error NotOperatorOrTimelock();

    // ==============================================================================
    // Events
    // ==============================================================================

    /// @notice When recoverEther is called
    /// @param amount The amount of Ether recovered
    event EmergencyEtherRecovered(uint256 amount);

    /// @notice When recoverErc20 is called
    /// @param tokenAddress The address of the ERC20 token being recovered
    /// @param tokenAmount The quantity of the token
    event EmergencyErc20Recovered(address tokenAddress, uint256 tokenAmount);

    /// @notice When frxETH is generated from submitted ETH
    /// @param sender The person who sent the ETH
    /// @param recipient The recipient of the frxETH
    /// @param sentEthAmount The amount of Eth sent
    event EthSubmitted(address indexed sender, address indexed recipient, uint256 sentEthAmount);

    /// @notice When togglePauseSubmits is called
    /// @param newStatus The new status of the pause
    event MintFrxEthPaused(bool newStatus);
}
