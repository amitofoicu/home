#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import time
import sys
import os
from datetime import datetime

def run_git_pull():
    """执行 git pull origin main 命令"""
    try:
        # 执行 git pull 命令
        result = subprocess.run(
            ['git', 'pull', 'origin', 'main'],
            capture_output=True,
            text=True,
            cwd=os.getcwd()  # 在当前目录执行
        )
        
        # 打印执行时间和结果
        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"\n[{current_time}] 执行 git pull origin main")
        print(f"返回码: {result.returncode}")
        
        if result.stdout:
            print("输出:", result.stdout.strip())
        if result.stderr:
            print("错误:", result.stderr.strip())
        
        # 判断是否成功
        if result.returncode == 0:
            if "Already up to date" in result.stdout:
                print("✅ 已经是最新版本")
                return True
            else:
                print("✅ 拉取成功，有更新")
                return True
        else:
            print("❌ 拉取失败")
            return False
            
    except Exception as e:
        print(f"❌ 执行出错: {e}")
        return False

def main():
    """主函数：每5分钟尝试一次，直到成功"""
    print("=" * 50)
    print("Git Pull 自动重试脚本")
    print("每5分钟尝试一次，直到成功")
    print("按 Ctrl+C 退出")
    print("=" * 50)
    
    attempt_count = 0
    
    while True:
        attempt_count += 1
        print(f"\n--- 第 {attempt_count} 次尝试 ---")
        
        # 执行 git pull
        success = run_git_pull()
        
        # 如果成功，退出循环
        if success:
            print("\n🎉 成功拉取代码！脚本结束。")
            break
        
        # 等待5分钟（300秒）
        next_time = datetime.now().timestamp() + 300
        next_time_str = datetime.fromtimestamp(next_time).strftime('%H:%M:%S')
        print(f"⏰ 等待5分钟，下次尝试时间: {next_time_str}")
        
        try:
            time.sleep(300)  # 300秒 = 5分钟
        except KeyboardInterrupt:
            print("\n👋 用户中断，脚本退出")
            sys.exit(0)

if __name__ == "__main__":
    main()