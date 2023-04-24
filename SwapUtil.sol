//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @return the address of the owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner());
        _;
    }

    /**
     * @return true if `msg.sender` is the owner of the contract.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     * It will not be possible to call the functions with the `onlyOwner`
     * modifier anymore.
     * @notice Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IERC20 {
    function balanceOf(address who) external view returns (uint256);
}
interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV3PoolActions {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    )external returns (
        int256 amount0,
        int256 amount1
    );
}
contract SwapBase is Ownable{
    address public  pair;
    address public  path0;
    address public  path1;
    constructor (
        address _pair,
        address _path0,
        address _path1
    ) payable {
        pair=_pair;
        path0=_path0;
        path1=_path1;
    }
    function init(
        address _pair,
        address _path0,
        address _path1
    ) external onlyOwner {
        if(pair==address(0)){
            pair=_pair;
        }
        if(path0==address(0)){
            path0=_path0;
        }
        if(path1==address(0)){
            path1=_path1;
        }
    }
    mapping (address  => bool) internal _approvals;
    address[] public approvals;
    function withdrawEth(address to) external onlyOwner {
        safeTransferETH(to, address(this).balance);
    }
    //add trader
    function setApprovals(address spender,bool value) external onlyOwner{
        _approvals[spender]=value;
        approvals.push(spender);
    }
    
    function getApprovals(address spender) external view returns(bool){
        return _approvals[spender];
    }
    function getApprovalsTimes() external view returns(uint){
        return approvals.length;
    }
    function safeTransfer(address token, address to,uint256 value)internal {
        functionCall(token, abi.encodeWithSelector(0xa9059cbb, to, value), 'MTF');//MydefiTransferHelper: TRANSFER_FAILED
    }

    function safeTransferETH(address to, uint256 value)internal {
        (bool success,) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    )internal {
        functionCall(token,abi.encodeWithSelector(0x23b872dd,from,to,value),'MTFF');//MydefiTransferHelper: TRANSFER_FROM_FAILED
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    )internal returns (bytes memory){
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    )internal pure returns (bytes memory){
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}
contract SwapUniswapV2Util is SwapBase{
    uint256 public immutable fee;
    constructor(address _pair,address _path0,address _path1,uint256 _fee)
        SwapBase(_pair,_path0,_path1){
        fee=_fee;
    }
    receive() external payable {}
    function skim(address token) external{
        require(_approvals[msg.sender],"a");//only approvals
        require(token!=path0);//only not token0
        require(token!=path1);//only not token1
        safeTransfer(
            token,
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }
    function withdrawToken0(
        uint amount
    )external onlyOwner{
        safeTransfer(path0, msg.sender, amount); 
    }
    function withdrawToken1(
        uint amount
    )external onlyOwner{
        safeTransfer(path1, msg.sender, amount); 
    }
    function depositToken0(
        uint amount
    )external onlyOwner{
        safeTransferFrom(path0, msg.sender,address(this), amount); 
    }
    function depositToken1(
        uint amount
    )external onlyOwner{
        safeTransferFrom(path1, msg.sender,address(this), amount); 
    }
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut,
        uint feeRate
    )internal pure returns (uint amountOut) {
        assembly {
            let amountInWithFee := mul(amountIn, feeRate)
            let numerator := mul(amountInWithFee, reserveOut)
            let denominator := add(mul(reserveIn, 10000), amountInWithFee)
            amountOut := div(numerator, denominator)
        }
    }
    function swapFromToken0(
        uint amountIn,
        uint amountOutMin
    )external returns (uint256 amount){
        require(_approvals[msg.sender],"a");//only approvals
        (uint112 reserve0,uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        amount=getAmountOut(amountIn, reserve0, reserve1,fee);
        require(amount>=amountOutMin, "IOT0");//INSUFFICIENT_OUTPUT_AMOUNT
        safeTransfer(path0, pair, amountIn); 
        IUniswapV2Pair(pair).swap(0, amount, address(this), new bytes(0));
    }
    function swapFromToken1(
        uint amountIn,
        uint amountOutMin
    )external returns (uint256 amount){
        require(_approvals[msg.sender],"a");//only approvals
        (uint112 reserve0,uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        amount=getAmountOut(amountIn, reserve1, reserve0,fee);
        require(amount>=amountOutMin, "IOT1");//INSUFFICIENT_OUTPUT_AMOUNT
        safeTransfer(path0, pair, amountIn); 
        IUniswapV2Pair(pair).swap(amount,0, address(this), new bytes(0));
    }
}
contract SwapUniswapV3Util is SwapBase{
    constructor(address _pair,address _path0,address _path1)SwapBase(_pair,_path0,_path1){}
    receive() external payable {}
    function skim(address token) external{
        require(_approvals[msg.sender],"a");//only approvals
        require(token!=path0);//only not token0
        require(token!=path1);//only not token1
        safeTransfer(
            token,
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }
    function withdrawToken0(
        uint amount
    )external onlyOwner{
        safeTransfer(path0, msg.sender, amount); 
    }
    function withdrawToken1(
        uint amount
    )external onlyOwner{
        safeTransfer(path1, msg.sender, amount); 
    }
    function depositToken0(
        uint amount
    )external onlyOwner{
        safeTransferFrom(path0, msg.sender,address(this), amount); 
    }
    function depositToken1(
        uint amount
    )external onlyOwner{
        safeTransferFrom(path1, msg.sender,address(this), amount); 
    }
    uint160 internal constant MIN_SQRT_RATIO = 4295128740;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970341;
    uint internal lock=0;
    function swapFromToken0ByPrice(
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )external returns (uint256 amount){
        require(_approvals[msg.sender],"a");//only approvals
        lock=1;
        (,int256 amount1)=IUniswapV3PoolActions(pair).swap(
            address(this),
            true,
            amountSpecified,
            sqrtPriceLimitX96,
            new bytes(0)
        );
        amount= uint256(-amount1);
    }
    function swapFromToken1ByPrice(
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )external returns (uint256 amount){
        require(_approvals[msg.sender],"IOT1");//only approvals
        lock=1;
        (int256 amount0,)=IUniswapV3PoolActions(pair).swap(
            address(this),
            false,
            amountSpecified,
            sqrtPriceLimitX96,
            new bytes(0)
        );
        amount= uint256(-amount0);
    }
    function swapFromToken0(
        int256 amountSpecified,
        uint256 amountOutMin
    )external returns (uint256 amount){
        require(_approvals[msg.sender],"a");//only approvals
        lock=1;
        (,int256 amount1)=IUniswapV3PoolActions(pair).swap(
            address(this),
            true,
            amountSpecified,
            MIN_SQRT_RATIO,
            new bytes(0)
        );
        amount= uint256(-amount1);
        require(amount>=amountOutMin, "IOT0");//INSUFFICIENT_OUTPUT_AMOUNT
    }
    function swapFromToken1(
        int256 amountSpecified,
        uint256 amountOutMin
    )external returns (uint256 amount){
        require(_approvals[msg.sender],"IOT1");//only approvals
        lock=1;
        (int256 amount0,)=IUniswapV3PoolActions(pair).swap(
            address(this),
            false,
            amountSpecified,
            MAX_SQRT_RATIO,
            new bytes(0)
        );
        amount= uint256(-amount0);
        require(amount>=amountOutMin, "IOT1");//INSUFFICIENT_OUTPUT_AMOUNT
    }
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    )external{
        if(data.length==0){
            _callback(amount0Delta,amount1Delta);
        }
    }
    function algebraSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external{
        if(data.length==0){
            _callback(amount0Delta,amount1Delta);
        }
    }
    function pancakeV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external{
        if(data.length==0){
            _callback(amount0Delta,amount1Delta);
        }
    }
    function _callback(
        int256 amount0Delta,
        int256 amount1Delta
    )internal{
        if(lock==1){
            lock=0;
            if (amount0Delta > 0) {
                safeTransfer(path0, pair, uint256(amount0Delta));
            } else {
                safeTransfer(path1, pair, uint256(amount1Delta));
            }
        }
    }
}
interface PairInfo {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract Config is Ownable{
    address[] public pairs;
    mapping(address => mapping(address => address)) public getPair;
    mapping(address =>uint256) public fees;
    mapping(address =>address) public swapPair;
    mapping(address =>uint256) public pairStates;
    
    mapping (address  => uint160) public fromSqrtPriceLimitX96s;
    mapping (address  => uint160) public toSqrtPriceLimitX96s;
    mapping (address  => uint) public swapLimit;
    function setFromSqrtPrice(address _pair,uint160 value) external onlyOwner{
        fromSqrtPriceLimitX96s[_pair]=value;
    }
    function setSwapLimit(address _pair,uint value) external onlyOwner{
        swapLimit[_pair]=value;
    }
    function setToSqrtPrice(address _pair,uint160 value) external onlyOwner{
        toSqrtPriceLimitX96s[_pair]=value;
    }
    address[] public allPairs;
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }
    function getAllReserves(address[] memory _pairs) public view returns (
        uint[] memory reserve0s, uint[] memory reserve1s
    ) {
        uint l=_pairs.length;
        reserve0s=new uint[](l);
        reserve1s=new uint[](l);
        for(uint i;i<l;i++){
            (reserve0s[i], reserve1s[i],) = IUniswapV2Pair(_pairs[i]).getReserves();
        }
    }
    function getAllPairsInf(
        uint start,
        uint end
    ) external view returns (
        address[] memory _swapPairs,
        address[] memory _pairs,
        address[] memory _token0s,
        address[] memory _token1s,
        uint256[] memory _fees,
        uint256[] memory _pairLmits,
        uint256[] memory _pairStates,
        uint160[] memory _fromPrice,
        uint160[] memory _toPrice
    ) {
        if(end>allPairs.length){
            end=allPairs.length;
        }
        uint l=end-start;
        _swapPairs=new address[](l);
        _pairs=new address[](l);
        _token0s=new address[](l);
        _token1s=new address[](l);
        _fees=new uint256[](l);
        _pairLmits=new uint256[](l);
        _pairStates=new uint256[](l);
        _fromPrice=new uint160[](l);
        _toPrice=new uint160[](l);
        for(uint i=start;i<end;i++){
            _pairs[i]=allPairs[i];
            _token0s[i]=PairInfo(_pairs[i]).token0();
            _token1s[i]=PairInfo(_pairs[i]).token1();
            _fees[i]=fees[_pairs[i]];
            _pairLmits[i]=swapLimit[_pairs[i]];
            _fromPrice[i]=fromSqrtPriceLimitX96s[_pairs[i]];
            _toPrice[i]=toSqrtPriceLimitX96s[_pairs[i]];
            _pairStates[i]=pairStates[_pairs[i]];
            _swapPairs[i]=swapPair[_pairs[i]];
        }
    }
    function addPair(address swapBase,uint256 fee) external onlyOwner {
        address token0=SwapBase(swapBase).path0();
        address token1=SwapBase(swapBase).path1();
        address pair=SwapBase(swapBase).pair();
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        fees[pair]=fee;
        swapPair[pair]=swapBase;
    }
    function setPair(address swapBase,uint256 fee) external onlyOwner {
        address token0=SwapBase(swapBase).path0();
        address token1=SwapBase(swapBase).path1();
        address pair=SwapBase(swapBase).pair();
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        fees[pair]=fee;
        swapPair[pair]=swapBase;
    }
    function setPairState(address pair,uint256 state) external onlyOwner {
        pairStates[pair]=state;
    }
 
}
//SwapV2Util  --  0xfc161A958185e5eb73435e9557cE5B5dCaC964B2
//SwapV3Util  --  0x155212075E426B66b28149c9fb7bb3d06337AC6B
//Config             --  0xe64490C1340040FCb5bb2dC907573C88eee8AF6E
