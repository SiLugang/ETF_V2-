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

    function investWithETH(//，
        address to,
        uint256 mintAmount,
        bytes[] memory swapPaths
    ) external payable {
        address[] memory tokens = getTokens();//传入tokens的地址数组
        if (tokens.length != swapPaths.length) revert InvalidArrayLength();//交易路径的长度必须相同，否则revert报错
        uint256[] memory tokenAmounts = getInvestTokenAmounts(mintAmount);//算出每个代币需要投入多少

        uint256 maxETHAmount = msg.value;//转入ETH的余额
        IWETH(weth).deposit{value: maxETHAmount}();//把当前接收的ETH，deposit转成WETH
        _approveToSwapRouter(weth);//weth代币授权给SwapRouter合约，调用WETH前需授权，196行逻辑：用完之后授权额度就不会变了，授权操作只需要做一次

        uint256 totalPaid;//记录，实际上总共支付了多少ETH
        for (uint256 i = 0; i < tokens.length; i++) {//循环，对每个代币进行循环操作
            if (tokenAmounts[i] == 0) continue;//tokenamount等于0，不需要做任何操作，不需要swap，直接返回
            if (!_checkSwapPath(tokens[i], weth, swapPaths[i]))//判断swapPath是否合规，206行逻辑：
                revert InvalidSwapPath(swapPaths[i]);//不合格报错
            if (tokens[i] == weth) {
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

        uint256 leftAfterPaid = maxETHAmount - totalPaid;
        IWETH(weth).withdraw(leftAfterPaid);
        payable(msg.sender).transfer(leftAfterPaid);

        _invest(to, mintAmount);

        emit InvestedWithETH(to, mintAmount, totalPaid);
    }

    function investWithToken(
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
        _approveToSwapRouter(srcToken);

        uint256 totalPaid;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] == 0) continue;
            if (!_checkSwapPath(tokens[i], srcToken, swapPaths[i]))
                revert InvalidSwapPath(swapPaths[i]);
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
            if (!_checkSwapPath(tokens[i], weth, swapPaths[i]))
                revert InvalidSwapPath(swapPaths[i]);
            if (tokens[i] == weth) {
                totalReceived += tokenAmounts[i];
            } else {
                _approveToSwapRouter(tokens[i]);
                totalReceived += IV3SwapRouter(swapRouter).exactInput(
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
    function _checkSwapPath(//逻辑：校验
        address tokenA,
        address tokenB,
        bytes memory path//tokenA/B/路径
    ) internal pure returns (bool) {//内部pure纯函数返回布尔值
        (address firstToken, address secondToken, ) = path.decodeFirstPool();
        if (tokenA == tokenB) {
            if (
                firstToken == tokenA &&
                secondToken == tokenA &&
                !path.hasMultiplePools()
            ) {
                return true;
            } else {
                return false;
            }
        } else {
            if (firstToken != tokenA) return false;
            while (path.hasMultiplePools()) {
                path = path.skipToken();
            }
            (, secondToken, ) = path.decodeFirstPool();
            if (secondToken != tokenB) return false;
            return true;
        }
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (!success) revert SafeTransferETHFailed();
    }
}
