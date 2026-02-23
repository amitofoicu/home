#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import time
import sys
import os
import argparse
from datetime import datetime

class GitAutoPush:
    def __init__(self, repo_path=None, commit_message=None, max_retries=None, wait_time=300):
        """
        初始化Git自动推送工具
        
        Args:
            repo_path: Git仓库路径，None表示使用当前目录
            commit_message: 提交信息，None表示让用户输入
            max_retries: 最大重试次数，None表示无限重试
            wait_time: 重试等待时间（秒），默认300秒（5分钟）
        """
        self.repo_path = repo_path or os.getcwd()
        self.commit_message = commit_message
        self.max_retries = max_retries
        self.wait_time = wait_time
        
    def run_command(self, command, description, cwd=None):
        """执行命令并返回结果"""
        working_dir = cwd or self.repo_path
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {description}...")
        try:
            result = subprocess.run(
                command, 
                shell=True, 
                capture_output=True, 
                text=True, 
                encoding='utf-8',
                cwd=working_dir
            )
            if result.returncode == 0:
                if result.stdout and result.stdout.strip():
                    for line in result.stdout.strip().split('\n'):
                        if line.strip():
                            print(f"  ✓ {line}")
                return True, result.stdout
            else:
                error_msg = result.stderr.strip() if result.stderr else "未知错误"
                print(f"  ✗ 失败: {error_msg}")
                return False, error_msg
        except Exception as e:
            print(f"  ✗ 异常: {str(e)}")
            return False, str(e)
    
    def check_repository(self):
        """检查指定路径是否是Git仓库"""
        print(f"\n📂 仓库路径: {self.repo_path}")
        return self.run_command("git rev-parse --git-dir", "检查Git仓库")
    
    def has_changes(self):
        """检查是否有文件变更"""
        success, output = self.run_command("git status --porcelain", "检查文件状态")
        return success and output.strip()
    
    def show_changed_files(self):
        """显示变更的文件列表"""
        success, output = self.run_command("git status -s", "查看变更文件")
        if success and output:
            print("\n📝 变更的文件:")
            files = output.strip().split('\n')
            for file in files:
                if file.startswith('??'):
                    print(f"  📄 新文件: {file[3:]}")
                elif file.startswith(' M'):
                    print(f"  ✏️ 修改: {file[3:]}")
                elif file.startswith('D '):
                    print(f"  🗑️ 删除: {file[3:]}")
                elif file.startswith('A '):
                    print(f"  ➕ 新增: {file[3:]}")
                elif file.startswith('R '):
                    print(f"  🔄 重命名: {file[3:]}")
                else:
                    print(f"  {file}")
        return success
    
    def get_commit_message_from_user(self):
        """获取用户输入的commit message"""
        print("\n" + "="*50)
        print("💬 请输入提交信息")
        print("="*50)
        print("提示: 直接回车使用自动生成的信息")
        print("    支持多行输入，空行结束（连续两次回车）")
        
        # 如果已经有预设的commit message
        if self.commit_message:
            print(f"\n预设信息: {self.commit_message}")
            use_preset = input("是否使用预设信息? (y/n, 默认y): ").strip().lower()
            if use_preset != 'n':
                return self.commit_message
        
        # 多行输入模式
        lines = []
        print("\n请输入提交信息（输入空行结束）:")
        
        while True:
            line = input()
            if line == "" and lines:  # 空行且已有内容，结束输入
                break
            elif line == "" and not lines:  # 第一个空行，继续等待
                continue
            lines.append(line)
        
        if lines:
            # 将多行信息用换行符连接
            return '\n'.join(lines)
        else:
            # 用户直接回车，使用自动生成的信息
            auto_message = f"自动提交: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            print(f"使用自动生成的信息: {auto_message}")
            return auto_message
    
    def git_add(self):
        """执行git add"""
        return self.run_command("git add .", "添加文件到暂存区")
    
    def git_commit(self, message):
        """执行git commit，使用提供的提交信息"""
        # 处理多行提交信息
        if '\n' in message:
            # 使用 -m 多次来处理多行信息
            cmd_parts = ['git commit']
            for line in message.split('\n'):
                if line.strip():  # 忽略空行
                    cmd_parts.append(f'-m "{line}"')
            cmd = ' '.join(cmd_parts)
        else:
            cmd = f'git commit -m "{message}"'
        
        return self.run_command(cmd, "提交更改")
    
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
            "Temporary failure in name resolution",
            "Connection was reset",
            "Recv failure",
            "unable to access",
            "OpenSSL SSL_read",
            "SSL connection",
            "Empty reply from server",
            "Connection aborted",
            "Connection closed",
            "Network error",
            "请求被中止",
            "连接被重置",
            "连接失败"
        ]
        error_lower = error_output.lower()
        return any(keyword.lower() in error_lower for keyword in network_error_keywords)
    
    def git_push(self):
        """执行git push"""
        return self.run_command("git push origin main", "推送代码到远程仓库")
    
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
                print(f"错误信息: {output[:100]}..." if len(output) > 100 else f"错误信息: {output}")
                
                # 倒计时
                for i in range(self.wait_time, 0, -1):
                    mins, secs = divmod(i, 60)
                    sys.stdout.write(f"\r⏳ 等待时间: {mins:02d}:{secs:02d} (按 Ctrl+C 取消)")
                    sys.stdout.flush()
                    time.sleep(1)
                print("\n")
            else:
                print(f"\n❌ 推送失败（非网络错误）")
                print(f"错误详情: {output}")
                return False
    
    def run(self):
        """运行完整的流程"""
        print("=" * 50)
        print("🚀 Git 自动提交推送工具")
        print("=" * 50)
        print(f"仓库路径: {self.repo_path}")
        print(f"重试策略: {'无限重试' if self.max_retries is None else f'最多{self.max_retries}次'}")
        print(f"等待时间: {self.wait_time//60}分钟")
        print("=" * 50)
        
        # 检查路径是否存在
        if not os.path.exists(self.repo_path):
            print(f"❌ 错误：路径不存在 - {self.repo_path}")
            return False
        
        # 检查Git仓库
        repo_success, _ = self.check_repository()
        if not repo_success:
            print("❌ 错误：指定路径不是Git仓库！")
            return False
        
        # 检查是否有变更
        if not self.has_changes():
            print("📝 没有文件需要提交，操作完成")
            return True
        
        # 显示变更的文件
        self.show_changed_files()
        
        # 获取用户输入的commit message
        commit_message = self.get_commit_message_from_user()
        
        # 执行git add
        add_success, _ = self.git_add()
        if not add_success:
            print("❌ git add失败，终止操作")
            return False
        
        # 执行git commit
        commit_success, _ = self.git_commit(commit_message)
        if not commit_success:
            print("❌ git commit失败，终止操作")
            return False
        
        # 执行git push（带重试）
        return self.push_with_retry()

def main():
    parser = argparse.ArgumentParser(description='Git自动提交推送工具')
    parser.add_argument('-p', '--path', help='Git仓库路径', default=None)
    parser.add_argument('-m', '--message', help='预设提交信息（可选）', default=None)
    parser.add_argument('-r', '--retries', type=int, help='最大重试次数', default=None)
    parser.add_argument('-w', '--wait', type=int, help='重试等待时间（秒）', default=300)
    parser.add_argument('-y', '--yes', action='store_true', help='使用自动生成的信息，不提示输入')
    
    args = parser.parse_args()
    
    # 如果没有指定路径，使用当前目录
    if not args.path:
        args.path = os.getcwd()
    
    # 如果指定了-y参数，使用自动生成的信息
    if args.yes and not args.message:
        args.message = f"自动提交: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
    
    tool = GitAutoPush(
        repo_path=args.path,
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