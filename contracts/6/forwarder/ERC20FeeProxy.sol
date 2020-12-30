pragma solidity 0.6.9;
pragma experimental ABIEncoderV2;

//to do, seperate into forwarderWithPersonalSign.sol and ERC20Forwarder.sol

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BiconomyForwarder.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IFeeManager.sol";
import "./ERC20ForwardRequestCompatible.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "hardhat/console.sol";

/**
 * @title ERC20 Fee Proxy
 *
 * @notice A contract for dApps to coordinate meta transactions paid for with ERC20 transfers
 *
 * @dev Inherits the ERC20ForwarderRequest struct via the contract of same name - essential for compatibility with The BiconomyForwarder
 * @dev Contract owner can set the feeManager contract & the feeReceiver address
 * @dev Tx Flow : call BiconomyForwarder to handle forwarding, call _transferHandler() to charge fee after
 *
 */
contract ERC20FeeProxy is ERC20ForwardRequestTypes,Ownable{

    using SafeMath for uint256;
    mapping(address=>uint256) public transferHandlerGas;
    mapping(address=>bool) public safeTransferRequired;
    address public feeReceiver;
    address public oracleAggregator;
    address public feeManager;
    address payable public forwarder;

    /**
     * @dev sets contract variables
     *
     * @param _feeReceiver : address that will receive fees charged in ERC20 tokens
     * @param _feeManager : the address of the contract that controls the charging of fees
     * @param _forwarder : the address of the BiconomyForwarder contract
     *
     */
    constructor(address _feeReceiver,address _feeManager,address payable _forwarder) public {
        feeReceiver = _feeReceiver;
        feeManager = _feeManager;
        forwarder = _forwarder;
    }

    function setOracleAggregator(address oa) external onlyOwner{
        oracleAggregator = oa;
    }

    /**
     * @dev enable dApps to change fee receiver addresses, e.g. for rotating keys/security purposes
     * @param _feeReceiver : address that will receive fees charged in ERC20 tokens */
    function setFeeReceiver(address _feeReceiver) external onlyOwner{
        feeReceiver = _feeReceiver;
    }

    /**
     * @dev enable dApps to change the contract that manages fee collection logic
     * @param _feeManager : the address of the contract that controls the charging of fees */
    function setFeeManager(address _feeManager) external onlyOwner{
        feeManager = _feeManager;
    }

    /**
     * @dev change amount of excess gas charged for _transferHandler
     * NOT INTENTED TO BE CALLED : may need to be called if :
     * - new feeManager consumes more/less gas
     * - token contract is upgraded to consume less gas
     * - etc
     */
     /// @param _transferHandlerGas : max amount of gas the function _transferHandler is expected to use
    function setTransferHandlerGas(address token, uint256 _transferHandlerGas) external onlyOwner{
        transferHandlerGas[token] = _transferHandlerGas;
    }

    function setSafeTransferRequired(address token, bool _safeTransferRequired) external onlyOwner{
        safeTransferRequired[token] = _safeTransferRequired;
    }

    /**
     * @dev calls the getNonce function of the BiconomyForwarder
     * @param from : the user address
     * @param batchId : the key of the user's batch being queried
     * @return nonce : the number of transaction made within said batch
     */
    function getNonce(address from, uint256 batchId)
    external view
    returns(uint256){
        uint256 nonce = BiconomyForwarder(forwarder).getNonce(from,batchId);
        return nonce;
    }

    /**
     * @dev
     * - Keeps track of gas consumed
     * - Calls BiconomyForwarder.executeEIP712 method using arguments given
     * - Calls _transferHandler, supplying the gas usage of the executeEIP712 call
     */
    /**
     * @param req : the request being forwarded
     * @param domainSeparator : the domain separator presented to the user when signing
     * @param sig : the signature generated by the user's wallet
     * @return success : false if call fails. true otherwise
     * @return ret : any return data from the call
     */
    function executeEIP712(
        ERC20ForwardRequest memory req,
        bytes32 domainSeparator,
        bytes calldata sig
        )
        external payable
        returns (bool success, bytes memory ret){
            uint256 initialGas = gasleft();
            (success,ret) = BiconomyForwarder(forwarder).executeEIP712(req,domainSeparator,sig);
            uint256 postGas = gasleft();
            uint256 charge = _transferHandler(req,initialGas.sub(postGas));
            emit FeeCharged(req.from,req.batchId,req.batchNonce,charge,req.token);
            console.log("ERC20FeeProxy.executeEIP712 gas usage : ",initialGas-gasleft());
    }

    /**
     * @dev
     * - Keeps track of gas consumed
     * - Calls BiconomyForwarder.executePersonalSign method using arguments given
     * - Calls _transferHandler, supplying the gas usage of the executePersonalSign call
    **/
    /**
     * @param req : the request being forwarded
     * @param sig : the signature generated by the user's wallet
     * @return success : false if call fails. true otherwise
     * @return ret : any return data from the call
     */
    function executePersonalSign(
        ERC20ForwardRequest memory req,
        bytes calldata sig
        )
        external payable
        returns (bool success, bytes memory ret){
            uint256 initialGas = gasleft();
            (success,ret) = BiconomyForwarder(forwarder).executePersonalSign(req,sig);
            uint256 postGas = gasleft();
            uint256 charge = _transferHandler(req,initialGas.sub(postGas));
            emit FeeCharged(req.from,req.batchId,req.batchNonce,charge,req.token);
            console.log("ERC20FeeProxy.executePersonalSign gas usage : ",initialGas-gasleft());
    }

    // Designed to enable linking to BiconomyForwarder events in external services such as The Graph
    event FeeCharged(address indexed from, uint256 batchId, uint256 batchNonce, uint256 indexed charge, address indexed token);

    /**
     * @dev
     * - Verifies if token supplied in request is allowed
     * - Transfers tokenGasPrice*totalGas*feeMultiplier $req.token, from req.to to feeReceiver
    **/
    /**
     * @param req : the request being forwarded
     * @param executionGas : amount of gas used to execute the forwarded request call
     */
    function _transferHandler(ERC20ForwardRequest memory req,uint256 executionGas) internal returns(uint256 charge){
        IFeeManager _feeManager = IFeeManager(feeManager);
        require(_feeManager.getTokenAllowed(req.token),"TOKEN NOT ALLOWED BY FEE MANAGER");
        uint gasleft0 = gasleft();
        charge = req.tokenGasPrice.mul(executionGas.add(transferHandlerGas[req.token])).mul(_feeManager.getFeeMultiplier(req.from,req.token)).div(10000);
        if (!safeTransferRequired[req.token]){
            console.log("if");
            require(IERC20(req.token).transferFrom(
            req.from,
            feeReceiver,
            charge));
        }
        else{
            console.log("else");
            SafeERC20.safeTransferFrom(IERC20(req.token), req.from,feeReceiver,charge);
        }
        uint gasUsed = gasleft0 - gasleft();
        console.log(gasUsed);
    }

}

