#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import time
import sys
import os
import argparse
from datetime import datetime

class GitAutoPush:
    def __init__(self, commit_message=None, max_retries=None, wait_time=300):
        """
        初始化Git自动推送工具
        
        Args:
            commit_message: 提交信息，None表示使用自动生成的信息
            max_retries: 最大重试次数，None表示无限重试
            wait_time: 重试等待时间（秒），默认300秒（5分钟）
        """
        self.commit_message = commit_message or f"自动提交: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        self.max_retries = max_retries
        self.wait_time = wait_time
        
    def run_command(self, command, description):
        """执行命令并返回结果"""
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {description}...")
        try:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, encoding='utf-8')
            if result.returncode == 0:
                if result.stdout and result.stdout.strip():
                    for line in result.stdout.strip().split('\n'):
                        print(f"  ✓ {line}")
                return True, result.stdout
            else:
                print(f"  ✗ 失败: {result.stderr}")
                return False, result.stderr
        except Exception as e:
            print(f"  ✗ 异常: {str(e)}")
            return False, str(e)
    
    def check_repository(self):
        """检查Git仓库"""
        return self.run_command("git rev-parse --git-dir", "检查Git仓库")
    
    def has_changes(self):
        """检查是否有文件变更"""
        success, output = self.run_command("git status --porcelain", "检查文件状态")
        return success and output.strip()
    
    def git_add(self):
        """执行git add"""
        return self.run_command("git add .", "添加文件到暂存区")
    
    def git_commit(self):
        """执行git commit"""
        return self.run_command(f'git commit -m "{self.commit_message}"', "提交更改")
    
    def git_push(self):
        """执行git push"""
        return self.run_command("git push origin main", "推送代码到远程仓库")
    
    def is_network_error(self, error_output):
        """判断是否是网络错误"""
        network_error_keywords = [
            "Could not resolve host",
            "Connection timed out",
            "Network is unreachable",
            "Failed to connect",
            "Connection refused",
            "操作超时",
            "无法连接到",
            "Timeout",
            "Temporary failure in name resolution"
        ]
        return any(keyword in error_output for keyword in network_error_keywords)
    
    def push_with_retry(self):
        """带重试的推送"""
        retry_count = 0
        
        while True:
            print(f"\n{'='*40}")
            print(f"推送尝试 #{retry_count + 1}")
            print(f"{'='*40}")
            
            success, output = self.git_push()
            
            if success:
                print("\n✨ 推送成功！")
                return True
            
            # 检查是否是网络错误
            if self.is_network_error(output):
                retry_count += 1
                
                if self.max_retries is not None and retry_count >= self.max_retries:
                    print(f"\n❌ 已达到最大重试次数 ({self.max_retries})，推送失败")
                    return False
                
                print(f"\n⚠ 检测到网络错误，{self.wait_time//60}分钟后重试...")
                print(f"当前时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
                
                # 倒计时
                for i in range(self.wait_time, 0, -1):
                    mins, secs = divmod(i, 60)
                    sys.stdout.write(f"\r⏳ 等待时间: {mins:02d}:{secs:02d}")
                    sys.stdout.flush()
                    time.sleep(1)
                print("\n")
            else:
                print("\n❌ 推送失败（非网络错误）")
                return False
    
    def run(self):
        """运行完整的流程"""
        print("=" * 50)
        print("🚀 Git 自动提交推送工具")
        print("=" * 50)
        print(f"提交信息: {self.commit_message}")
        print(f"重试策略: {'无限重试' if self.max_retries is None else f'最多{self.max_retries}次'}")
        print(f"等待时间: {self.wait_time//60}分钟")
        print("=" * 50)
        
        # 检查Git仓库
        repo_success, _ = self.check_repository()
        if not repo_success:
            print("❌ 错误：当前目录不是Git仓库！")
            return False
        
        # 检查是否有变更
        if not self.has_changes():
            print("📝 没有文件需要提交，操作完成")
            return True
        
        # 执行git add
        add_success, _ = self.git_add()
        if not add_success:
            print("❌ git add失败，终止操作")
            return False
        
        # 执行git commit
        commit_success, _ = self.git_commit()
        if not commit_success:
            print("❌ git commit失败，终止操作")
            return False
        
        # 执行git push（带重试）
        return self.push_with_retry()

def main():
    parser = argparse.ArgumentParser(description='Git自动提交推送工具')
    parser.add_argument('-m', '--message', help='提交信息', default=None)
    parser.add_argument('-r', '--retries', type=int, help='最大重试次数', default=None)
    parser.add_argument('-w', '--wait', type=int, help='重试等待时间（秒）', default=300)
    
    args = parser.parse_args()
    
    tool = GitAutoPush(
        commit_message=args.message,
        max_retries=args.retries,
        wait_time=args.wait
    )
    
    try:
        success = tool.run()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n👋 用户中断操作")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 发生错误: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()