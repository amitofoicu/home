@echo off
title 地藏经播放脚本
echo ===== 地藏经播放脚本 =====
echo 此脚本设计用于Windows任务计划程序调用
echo.

:: 设置音量为适当值
if exist "C:\Windows\System32\nircmd.exe" (
    echo 设置系统音量...
    nircmd setsysvolume 100
    nircmd mutesysvolume 0
) else (
    echo 警告：未找到 nircmd.exe，无法调整音量
    echo 请确保 nircmd.exe 位于 C:\Windows\System32\ 目录下
)

:: 打开网页并自动全屏（使用Edge浏览器）
echo 正在打开视频网页并自动全屏...
start msedge --start-fullscreen "https://www.fashui.org/#/videoplay?menuidparent=14&menuidchild=12&voice=&mp4=1&numbers=284116"

echo ===== 播放已启动 =====
echo 视频已在Edge浏览器中以全屏模式播放
echo.

exit