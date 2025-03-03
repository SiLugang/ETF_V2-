// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ETFv1} from "./ETFv1.sol";
import {IETFv2} from "./interfaces/IETFv2.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {Path} from "./libraries/Path.sol";
import {SafeERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts@5.1.0/token/ERC20/IERC20.sol";
import {IV3SwapRouter} from "./interfaces/IV3SwapRouter.sol";

contract ETFv2 is IETFv2, ETFv1 {//ETFv2继承自IETFv2，ETFv1
    using SafeERC20 for IERC20;//safeERC20函数用于安全兼容的交互ERC20的token
    using Path for bytes;//用于存储token间的兑换路径

    address public immutable swapRouter;//不可变的变量swaprouter
    address public immutable weth;//不可变的状态变量，weth

    constructor(
        string memory name_,//名称
        string memory symbol_,//代币标识
        address[] memory tokens_,//ETF组成代币构成的数组
        uint256[] memory initTokenAmountPerShare_,//？
        uint256 minMintAmount_,//最小mint
        address swapRouter_,//地址类型的swap
        address weth_//地址类型的weth
    ) ETFv1(name_, symbol_, tokens_, initTokenAmountPerShare_, minMintAmount_) {//参数传过去
        swapRouter = swapRouter_;//赋值swapRouter
        weth = weth_;//赋值weth
    }

    receive() external payable {}//意外要用到ETH，所以需要声明，定义receive()函数，如果不声明是没办法接收ETH的

    function investWithETH(//用ETH进行invest的实现逻辑
        address to,
        uint256 mintAmount,
        bytes[] memory swapPaths
    ) external payable {
        address[] memory tokens = getTokens();//传入tokens的地址数组
        if (tokens.length != swapPaths.length) revert InvalidArrayLength();//交易路径的长度必须相同，否则revert报错
        uint256[] memory tokenAmounts = getInvestTokenAmounts(mintAmount);//算出每个代币需要投入多少

        uint256 maxETHAmount = msg.value;//转入ETH的余额
        IWETH(weth).deposit{value: maxETHAmount}();//把当前接收的ETH，deposit转成WETH，这个是实际的WETH
        _approveToSwapRouter(weth);//weth代币授权给SwapRouter合约，调用WETH前需授权，196行逻辑：用完之后授权额度就不会变了，授权操作只需要做一次

        uint256 totalPaid;//记录，实际上总共支付了多少ETH
        for (uint256 i = 0; i < tokens.length; i++) {//循环，对每个代币进行循环操作
            if (tokenAmounts[i] == 0) continue;//tokenamount等于0，不需要做任何操作，不需要swap，直接返回；//50：tokens[i]是output的token，weth是input的token
            if (!_checkSwapPath(tokens[i], weth, swapPaths[i]))//***1.判断swapPath是否合规，206行逻辑：校验path：判断A是不是第一个，B是不是最后一个；2.需考虑顺序，tokensi等于tokenamount这个是确定的
                revert InvalidSwapPath(swapPaths[i]);//不合格报错;//用weth去兑换tokens[i]，输出金额是确定的，输入不确定
            if (tokens[i] == weth) {//做一个区分，如果token[i]=实际的weth，说明支付的是ETH，就没必要再去swap一次
                totalPaid += tokenAmounts[i];//此时直接记账＋到totalpay里
            } else {
                totalPaid += IV3SwapRouter(swapRouter).exactOutput(//***调UniSwapV3，在exactOutput里是用weth换tokens[i],在101行
                    IV3SwapRouter.ExactOutputParams({
                        path: swapPaths[i],//swap路径，需考虑顺序
                        recipient: address(this),//接收到当前的合约地址里
                        amountOut: tokenAmounts[i],//Amount总数
                        amountInMaximum: type(uint256).max//为了简便？设为最大值？
                    })//执行完成后，会返回实际执行了多少，累加到totalpaid里面
                );
            }
        }//循环结束，算出实际支付的数量是多少

        uint256 leftAfterPaid = maxETHAmount - totalPaid;//原本支付的代币-实际支付的=剩下的代币？原本支付是哪个数值，和实际支付有什么不同
        IWETH(weth).withdraw(leftAfterPaid);//剩下的把它做一个withdraw，把weth转成eth
        payable(msg.sender).transfer(leftAfterPaid);//***然后还给用户

        _invest(to, mintAmount);//底层invest操作

        emit InvestedWithETH(to, mintAmount, totalPaid);//抛出事件：地址，mint总数，实际支付
    }

    function investWithToken(//和ETH基本相同，只是不需要ETH和WETH互换（为了兼容ERC20），其他token本来就是ERC20代币
        address srcToken,
        address to,
        uint256 mintAmount,
        uint256 maxSrcTokenAmount,
        bytes[] memory swapPaths
    ) external {
        address[] memory tokens = getTokens();
        if (tokens.length != swapPaths.length) revert InvalidArrayLength();
        uint256[] memory tokenAmounts = getInvestTokenAmounts(mintAmount);

        IERC20(srcToken).safeTransferFrom(
            msg.sender,
            address(this),
            maxSrcTokenAmount
        );
        _approveToSwapRouter(srcToken);//对每个代币，授权操作只需进行1次，函数逻辑在196行

        uint256 totalPaid;//实际总共支付的ETH会记录下来
        for (uint256 i = 0; i < tokens.length; i++) {//对每个代币循环
            if (tokenAmounts[i] == 0) continue;//如果tokenAmount（下面展示的代币）=0，说明不需要做swap，会直接返回
            if (!_checkSwapPath(tokens[i], srcToken, swapPaths[i]))//检查path是否合法，checkSwappath（）函数：206行
                revert InvalidSwapPath(swapPaths[i]);//不合法时报错
            if (tokens[i] == srcToken) {
                totalPaid += tokenAmounts[i];
            } else {
                totalPaid += IV3SwapRouter(swapRouter).exactOutput(
                    IV3SwapRouter.ExactOutputParams({
                        path: swapPaths[i],
                        recipient: address(this),
                        amountOut: tokenAmounts[i],
                        amountInMaximum: type(uint256).max
                    })
                );
            }
        }

        uint256 leftAfterPaid = maxSrcTokenAmount - totalPaid;
        IERC20(srcToken).safeTransfer(msg.sender, leftAfterPaid);

        _invest(to, mintAmount);

        emit InvestedWithToken(srcToken, to, mintAmount, totalPaid);
    }

    function redeemToETH(
        address to,
        uint256 burnAmount,
        uint256 minETHAmount,
        bytes[] memory swapPaths
    ) external {
        address[] memory tokens = getTokens();
        if (tokens.length != swapPaths.length) revert InvalidArrayLength();

        uint256[] memory tokenAmounts = _redeem(address(this), burnAmount);

        uint256 totalReceived;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] == 0) continue;
            if (!_checkSwapPath(tokens[i], weth, swapPaths[i]))//path里第一个是input，第二个是output，
                revert InvalidSwapPath(swapPaths[i]);
            if (tokens[i] == weth) {
                totalReceived += tokenAmounts[i];
            } else {
                _approveToSwapRouter(tokens[i]);
                totalReceived += IV3SwapRouter(swapRouter).exactInput(//执行input时，path里第一个是input，第二个是output，和exactinput刚好相反，
                    IV3SwapRouter.ExactInputParams({
                        path: swapPaths[i],
                        recipient: address(this),
                        amountIn: tokenAmounts[i],
                        amountOutMinimum: 1
                    })
                );
            }
        }

        if (totalReceived < minETHAmount) revert OverSlippage();
        IWETH(weth).withdraw(totalReceived);
        _safeTransferETH(to, totalReceived);

        emit RedeemedToETH(to, burnAmount, totalReceived);
    }

    function redeemToToken(
        address dstToken,
        address to,
        uint256 burnAmount,
        uint256 minDstTokenAmount,
        bytes[] memory swapPaths
    ) external {
        address[] memory tokens = getTokens();
        if (tokens.length != swapPaths.length) revert InvalidArrayLength();

        uint256[] memory tokenAmounts = _redeem(address(this), burnAmount);

        uint256 totalReceived;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] == 0) continue;
            if (!_checkSwapPath(tokens[i], dstToken, swapPaths[i]))
                revert InvalidSwapPath(swapPaths[i]);
            if (tokens[i] == dstToken) {
                IERC20(tokens[i]).safeTransfer(to, tokenAmounts[i]);
                totalReceived += tokenAmounts[i];
            } else {
                _approveToSwapRouter(tokens[i]);
                totalReceived += IV3SwapRouter(swapRouter).exactInput(
                    IV3SwapRouter.ExactInputParams({
                        path: swapPaths[i],
                        recipient: to,
                        amountIn: tokenAmounts[i],
                        amountOutMinimum: 1
                    })
                );
            }
        }

        if (totalReceived < minDstTokenAmount) revert OverSlippage();

        emit RedeemedToToken(dstToken, to, burnAmount, totalReceived);
    }

    function _approveToSwapRouter(address token) internal {//approve的逻辑：用完之后授权额度就不会变了
        if (
            IERC20(token).allowance(address(this), swapRouter) <//判断，从token拿出allowances，如果allowances小于max最大值那么授权最大值
            type(uint256).max//这个是什么？
        ) {
            IERC20(token).forceApprove(swapRouter, type(uint256).max);
        }
    }

    // The first token in the path must be tokenA, the last token must be tokenB
    function _checkSwapPath(//逻辑：校验path：判断A是不是第一个，B是不是最后一个。只用校验这两个？对path需要校验吗
        address tokenA,
        address tokenB,
        bytes memory path//tokenA/B，路径
    ) internal pure returns (bool) {//内部pure纯函数，返回布尔值（t/f）
        (address firstToken, address secondToken, ) = path.decodeFirstPool();//把第一个池子拿出来
        if (tokenA == tokenB) {//如果相等，两代币是一样的-------A--fee--A；场景：支付WBTC、列表也有WBTC
            if (
                firstToken == tokenA &&
                secondToken == tokenA &&
                !path.hasMultiplePools()//第一第二token都是wokenA，没有多个池子（单一池子）
            ) {
                return true;//A=B的情况下返回ture
            } else {//其他情况
                return false;
            }
        } else {//如果A代币！=B代币，那么第一代币必须等于tokenA
            if (firstToken != tokenA) return false;
            while (path.hasMultiplePools()) {//当有多个池子的情况下，为了拿到最后一个token？怎么拿到：
                path = path.skipToken();//在前面有多个池子时，跳过第一个交换池子，直到不是multiple池子后跳出
            }
            (, secondToken, ) = path.decodeFirstPool();//此时只剩单一池子，做一个decode，返回两个代币的地址和fee；secondToken=最后一个tokenD
            if (secondToken != tokenB) return false;//最后一个tokenD必须等于tokenB
            return true;
        }
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (!success) revert SafeTransferETHFailed();
    }
}
