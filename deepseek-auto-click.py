import pyautogui
import time
import sys
import random
import json
import os
from PIL import Image

# 配置文件路径
CONFIG_FILE = "scroll_config.json"

def load_last_coordinates():
    """加载上一次保存的坐标"""
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                config = json.load(f)
                return config.get('last_x'), config.get('last_y')
    except Exception as e:
        print(f"加载配置文件失败: {e}")
    return None, None

def save_last_coordinates(x, y):
    """保存坐标到配置文件"""
    try:
        config = {}
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                config = json.load(f)
        
        config['last_x'] = x
        config['last_y'] = y
        
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2)
        print(f"坐标 ({x}, {y}) 已保存")
    except Exception as e:
        print(f"保存配置文件失败: {e}")

def scroll_at_coordinate(x, y, scroll_amount, scroll_name="scroll"):
    """
    在指定坐标位置执行滚动操作
    scroll_amount: 负数向下滚动，正数向上滚动
    """
    # 保存当前鼠标位置
    original_pos = pyautogui.position()
    
    # 移动到目标坐标附近（但不是精确位置，避免干扰）
    offset_x = random.randint(-20, 20)
    offset_y = random.randint(-20, 20)
    move_x = x + offset_x
    move_y = y + offset_y
    
    # 确保坐标在屏幕范围内
    screen_width, screen_height = pyautogui.size()
    move_x = max(0, min(move_x, screen_width - 1))
    move_y = max(0, min(move_y, screen_height - 1))
    
    # 移动到目标位置并滚动
    pyautogui.moveTo(move_x, move_y, duration=0.2)
    time.sleep(0.1)
    pyautogui.scroll(scroll_amount)
    
    # 移回原始位置
    pyautogui.moveTo(original_pos.x, original_pos.y, duration=0.2)
    
    direction = "向下" if scroll_amount < 0 else "向上"
    print(f"在坐标 ({x}, {y}) 附近执行{scroll_name}: {direction} {abs(scroll_amount)} 单位")
    time.sleep(0.2)
    
    return True

def simulate_coordinate_scroll(x, y, scroll_attempt=1):
    """
    基于坐标位置模拟滚动操作
    """
    scroll_strategies = []
    
    if scroll_attempt == 1:
        # 第一次尝试：中等幅度向下滚动
        scroll_amount = random.randint(-150, -100)
        scroll_at_coordinate(x, y, scroll_amount, "初次滚动")
        
    elif scroll_attempt == 2:
        # 第二次尝试：组合滚动（先上后下）
        scroll_at_coordinate(x, y, random.randint(50, 80), "轻微向上")
        time.sleep(0.3)
        scroll_at_coordinate(x, y, random.randint(-200, -160), "中等向下")
        
    elif scroll_attempt == 3:
        # 第三次尝试：大幅度向下滚动
        scroll_amount = random.randint(-350, -250)
        scroll_at_coordinate(x, y, scroll_amount, "大幅度滚动")
        
    else:
        # 后续尝试：随机模式
        if random.random() > 0.5:
            # 上下组合滚动
            for i in range(2):
                scroll_at_coordinate(x, y, random.randint(-180, -120), f"连续向下{i+1}")
                time.sleep(0.2)
        else:
            # 先小幅度上，再大幅度下
            scroll_at_coordinate(x, y, random.randint(30, 60), "调整向上")
            time.sleep(0.4)
            scroll_at_coordinate(x, y, random.randint(-280, -220), "强力向下")
    
    print(f"第{scroll_attempt}次坐标滚动尝试完成")
    return True

def check_pixel_changes(screenshot, previous_pixels=None, threshold=15):
    """
    检测像素变化，修复Pillow弃用警告
    """
    try:
        # 优先使用新方法
        current_pixels = list(screenshot.get_flattened_data())
    except AttributeError:
        try:
            # 备用方法
            current_pixels = list(screenshot.getdata())
        except:
            # 最后尝试手动转换
            current_pixels = []
            for pixel in screenshot.getdata():
                if isinstance(pixel, tuple):
                    # 将RGB转换为单值
                    r, g, b = pixel[:3]
                    current_pixels.append((r << 16) | (g << 8) | b)
    
    unique_colors = len(set(current_pixels))
    
    # 如果有之前的像素数据，计算变化率
    if previous_pixels:
        if len(current_pixels) != len(previous_pixels):
            return unique_colors > threshold, current_pixels
        
        # 计算像素差异百分比
        changed_pixels = sum(1 for i in range(len(current_pixels)) 
                           if current_pixels[i] != previous_pixels[i])
        change_percentage = changed_pixels / len(current_pixels) * 100
        
        # 如果变化超过10%，认为有显著变化
        if change_percentage > 10:
            print(f"像素变化率: {change_percentage:.2f}%")
            return True, current_pixels
    
    # 基础检查：颜色多样性
    return unique_colors > threshold, current_pixels

def get_pixel_data(screenshot):
    """
    统一获取像素数据的方法，兼容不同Pillow版本
    """
    try:
        # 尝试新方法
        return list(screenshot.get_flattened_data())
    except AttributeError:
        try:
            # 尝试旧方法
            return list(screenshot.getdata())
        except:
            # 手动处理
            pixels = []
            for pixel in screenshot.getdata():
                if isinstance(pixel, tuple) and len(pixel) >= 3:
                    r, g, b = pixel[0], pixel[1], pixel[2]
                    pixels.append((r << 16) | (g << 8) | b)
                else:
                    pixels.append(pixel)
            return pixels

def monitor_and_click_optimized(target_x, target_y, check_interval=2, max_scroll_attempts=5):
    """
    优化的监控点击函数，包含基于坐标的滚动检测机制
    """
    print(f"开始监控坐标 ({target_x}, {target_y})")
    print(f"检查间隔: {check_interval}秒")
    print(f"最大滚动尝试次数: {max_scroll_attempts}次")
    print("按 'Ctrl+C' 停止监控")
    print("当连续检测不到变化时，程序会暂停检测，按Enter键恢复...")
    
    click_count = 0
    no_change_count = 0
    previous_pixels = None
    scroll_attempts = 0
    paused = False
    
    # 监控区域
    region_width, region_height = 50, 50
    region = (target_x - region_width//2, target_y - region_height//2, region_width, region_height)
    
    try:
        while True:
            # 检查是否暂停
            if paused:
                print("\n=== 检测暂停中 ===")
                print("按Enter键恢复检测，或按Ctrl+C完全停止...")
                try:
                    input()  # 等待用户按Enter
                    paused = False
                    no_change_count = 0
                    scroll_attempts = 0
                    previous_pixels = None
                    print("恢复检测...")
                    continue
                except KeyboardInterrupt:
                    print("\n用户中断，停止监控")
                    break
                except Exception as e:
                    print(f"恢复检测时出错: {e}")
                    time.sleep(1)
                    continue
            
            try:
                screenshot = pyautogui.screenshot(region=region)
            except Exception as e:
                print(f"区域截图失败: {e}")
                # 如果区域截图失败，尝试全屏截图
                try:
                    screenshot = pyautogui.screenshot()
                    # 从全屏截图中裁剪目标区域
                    screen_width, screen_height = pyautogui.size()
                    crop_x1 = max(0, target_x - region_width//2)
                    crop_y1 = max(0, target_y - region_height//2)
                    crop_x2 = min(screen_width, crop_x1 + region_width)
                    crop_y2 = min(screen_height, crop_y1 + region_height)
                    screenshot = screenshot.crop((crop_x1, crop_y1, crop_x2, crop_y2))
                except Exception as e2:
                    print(f"截图失败: {e2}")
                    time.sleep(check_interval)
                    continue
            
            # 使用统一的像素数据获取方法
            current_pixels = get_pixel_data(screenshot)
            
            # 检测像素变化
            has_changed = False
            unique_colors = len(set(current_pixels))
            
            if previous_pixels:
                if len(current_pixels) == len(previous_pixels):
                    # 计算像素差异百分比
                    changed_pixels = sum(1 for i in range(len(current_pixels)) 
                                       if current_pixels[i] != previous_pixels[i])
                    change_percentage = changed_pixels / len(current_pixels) * 100
                    
                    # 如果变化超过10%，认为有显著变化
                    if change_percentage > 10:
                        print(f"像素变化率: {change_percentage:.2f}%")
                        has_changed = True
            else:
                # 第一次检测，如果有足够颜色就认为可能有内容
                has_changed = unique_colors > 20
            
            previous_pixels = current_pixels
            
            if has_changed:
                no_change_count = 0
                scroll_attempts = 0
                
                # 检查是否是有效点击区域（非纯色背景）
                if unique_colors > 30:  # 按钮通常有更多颜色
                    click_count += 1
                    print(f"[{click_count}] 检测到有效变化，点击坐标 ({target_x}, {target_y}) - {time.strftime('%H:%M:%S')}")
                    
                    # 点击前确保鼠标在正确位置
                    pyautogui.moveTo(target_x, target_y, duration=0.1)
                    time.sleep(0.05)
                    pyautogui.click(target_x, target_y)
                    
                    # 点击后等待更长时间，避免快速重复点击
                    wait_time = random.uniform(2.5, 4.0)
                    print(f"点击后等待 {wait_time:.1f} 秒")
                    time.sleep(wait_time)
                    
                    # 点击后重置监控
                    previous_pixels = None
                    time.sleep(check_interval)
                    continue
            else:
                no_change_count += 1
                print(f"无变化检测次数: {no_change_count} (颜色数: {unique_colors})")
                
                # 如果连续多次无变化，尝试基于坐标滚动
                if no_change_count >= 5 and scroll_attempts < max_scroll_attempts:
                    print(f"尝试第{scroll_attempts + 1}次坐标滚动...")
                    simulate_coordinate_scroll(target_x, target_y, scroll_attempts + 1)
                    scroll_attempts += 1
                    no_change_count = 0  # 重置计数
                    
                    # 滚动后等待页面稳定
                    wait_time = 1.0 + scroll_attempts * 0.3
                    print(f"滚动后等待 {wait_time:.1f} 秒让页面稳定")
                    time.sleep(wait_time)
                    
                    # 滚动后重置像素状态
                    previous_pixels = None
                
                # 如果已经达到最大滚动次数，仍然没有变化，则暂停检测
                elif no_change_count >= 10 and scroll_attempts >= max_scroll_attempts:
                    print(f"\n=== 已达到最大滚动次数 ({max_scroll_attempts})，连续 {no_change_count} 次无变化 ===")
                    print("暂停检测，等待用户干预...")
                    paused = True
                    no_change_count = 0
                    continue
            
            time.sleep(check_interval)
            
    except KeyboardInterrupt:
        print(f"\n监控停止，总共点击 {click_count} 次")
        # 保存当前坐标
        save_last_coordinates(target_x, target_y)
    except Exception as e:
        print(f"发生错误: {e}")
        import traceback
        traceback.print_exc()

def get_mouse_position():
    """获取当前鼠标位置"""
    print("请在3秒内将鼠标移动到目标位置...")
    time.sleep(2)
    
    positions = []
    for i in range(3, 0, -1):
        x, y = pyautogui.position()
        positions.append((x, y))
        print(f"鼠标位置: ({x}, {y}) - {i}秒后获取最终位置")
        time.sleep(1)
    
    avg_x = sum(p[0] for p in positions) // len(positions)
    avg_y = sum(p[1] for p in positions) // len(positions)
    
    print(f"\n最终坐标: ({avg_x}, {avg_y})")
    return avg_x, avg_y

def test_coordinate_scroll():
    """测试坐标滚动功能"""
    print("\n=== 坐标滚动功能测试 ===")
    print("请先获取要测试的坐标位置...")
    
    x, y = get_mouse_position()
    
    print(f"\n将在坐标 ({x}, {y}) 进行滚动测试...")
    print("将测试3种不同的滚动策略")
    
    test_scenarios = [
        ("第一次滚动尝试（中等向下）", 1),
        ("第二次滚动尝试（先上后下）", 2),
        ("第三次滚动尝试（大幅度向下）", 3),
        ("额外滚动尝试（随机模式）", 4),
    ]
    
    for desc, attempt in test_scenarios:
        input(f"\n按Enter进行{desc}...")
        simulate_coordinate_scroll(x, y, attempt)
        time.sleep(1)
    
    print("\n坐标滚动测试完成！")
    return x, y

def coordinate_scroll_demo():
    """坐标滚动演示"""
    print("\n=== 坐标滚动演示 ===")
    print("1. 获取新坐标并测试滚动")
    print("2. 使用指定坐标测试滚动")
    print("3. 返回主菜单")
    
    choice = input("\n请选择 (1-3): ")
    
    if choice == '1':
        x, y = test_coordinate_scroll()
        input(f"\n测试完成，坐标 ({x}, {y}) 已记录\n按Enter返回...")
        return x, y
    elif choice == '2':
        try:
            x = int(input("请输入X坐标: "))
            y = int(input("请输入Y坐标: "))
        except:
            print("输入无效，使用上次记忆坐标")
            last_x, last_y = load_last_coordinates()
            if last_x is not None and last_y is not None:
                x, y = last_x, last_y
            else:
                x, y = 1806, 831
        
        print(f"\n在坐标 ({x}, {y}) 测试滚动...")
        simulate_coordinate_scroll(x, y, 1)
        time.sleep(0.5)
        simulate_coordinate_scroll(x, y, 2)
        return x, y
    else:
        return None, None

if __name__ == "__main__":
    print("=== 坐标感知版自动点击监控工具 ===")
    print("特点：基于捕获的坐标位置进行滚动操作")
    print("=" * 50)
    
    # 加载上一次保存的坐标
    last_x, last_y = load_last_coordinates()
    saved_x, saved_y = last_x, last_y
    
    # 如果有上次记忆的坐标，询问是否直接启动
    if saved_x is not None and saved_y is not None:
        print(f"\n检测到上次记忆的坐标: ({saved_x}, {saved_y})")
        auto_start = input("是否直接使用此坐标开始监控？(Y/n): ").strip().lower()
        
        if auto_start == '' or auto_start == 'y' or auto_start == 'yes':
            print(f"\n使用记忆坐标 ({saved_x}, {saved_y}) 自动启动监控...")
            
            # 设置检查间隔（默认2秒）
            try:
                interval_input = input(f"请输入检查间隔(秒，直接回车使用默认2秒): ").strip()
                if interval_input:
                    interval = float(interval_input)
                else:
                    interval = 2
                    print(f"使用默认间隔: {interval}秒")
            except:
                interval = 2
                print(f"输入无效，使用默认间隔: {interval}秒")
            
            # 设置最大滚动尝试次数（默认5次）
            try:
                max_scroll_input = input(f"请输入最大滚动尝试次数(直接回车使用默认5次): ").strip()
                if max_scroll_input:
                    max_scroll = int(max_scroll_input)
                else:
                    max_scroll = 5
                    print(f"使用默认最大滚动次数: {max_scroll}次")
            except:
                max_scroll = 5
                print(f"输入无效，使用默认最大滚动次数: {max_scroll}次")
            
            print(f"\n开始监控，将自动处理隐藏按钮...")
            print(f"监控坐标: ({saved_x}, {saved_y})")
            print(f"检查间隔: {interval}秒")
            print(f"最大滚动尝试: {max_scroll}次")
            print("当连续检测不到变化时，程序会暂停检测，按Enter键恢复...")
            print("=" * 50)
            
            monitor_and_click_optimized(saved_x, saved_y, check_interval=interval, max_scroll_attempts=max_scroll)
            
            # 监控结束后询问是否继续
            continue_choice = input("\n监控已停止，是否返回主菜单？(y/n): ")
            if continue_choice.lower() != 'y':
                print("退出程序")
                sys.exit(0)
    
    while True:
        print("\n主菜单:")
        if saved_x is not None and saved_y is not None:
            print(f"当前记忆坐标: ({saved_x}, {saved_y})")
        print("1. 获取新坐标位置并开始监控")
        print("2. 使用指定坐标开始监控")
        print("3. 坐标滚动演示和测试")
        print("4. 退出")
        
        choice = input("\n请选择 (1-4): ").strip()
        
        if choice == '1':
            x, y = get_mouse_position()
            saved_x, saved_y = x, y
            save_last_coordinates(x, y)
        elif choice == '2':
            try:
                x = int(input("请输入X坐标: "))
                y = int(input("请输入Y坐标: "))
                saved_x, saved_y = x, y
                save_last_coordinates(x, y)
            except:
                print("输入无效，使用记忆坐标或默认坐标")
                if saved_x is not None and saved_y is not None:
                    x, y = saved_x, saved_y
                else:
                    x, y = 1806, 831
                    saved_x, saved_y = x, y
        elif choice == '3':
            demo_x, demo_y = coordinate_scroll_demo()
            if demo_x is not None:
                saved_x, saved_y = demo_x, demo_y
                save_last_coordinates(demo_x, demo_y)
                print(f"演示完成，坐标 ({saved_x}, {saved_y}) 已保存")
            continue
        elif choice == '4':
            print("退出程序")
            sys.exit(0)
        else:
            print("无效选择，请重试")
            continue
        
        if saved_x is None or saved_y is None:
            print("未获取到有效坐标，请重试")
            continue
        
        # 设置检查间隔（默认2秒）
        try:
            interval_input = input(f"请输入检查间隔(秒，直接回车使用默认2秒): ").strip()
            if interval_input:
                interval = float(interval_input)
            else:
                interval = 2
                print(f"使用默认间隔: {interval}秒")
        except:
            interval = 2
            print(f"输入无效，使用默认间隔: {interval}秒")
        
        # 设置最大滚动尝试次数（默认5次）
        try:
            max_scroll_input = input(f"请输入最大滚动尝试次数(直接回车使用默认5次): ").strip()
            if max_scroll_input:
                max_scroll = int(max_scroll_input)
            else:
                max_scroll = 5
                print(f"使用默认最大滚动次数: {max_scroll}次")
        except:
            max_scroll = 5
            print(f"输入无效，使用默认最大滚动次数: {max_scroll}次")
        
        print(f"\n开始监控，将自动处理隐藏按钮...")
        print(f"监控坐标: ({saved_x}, {saved_y})")
        print(f"检查间隔: {interval}秒")
        print(f"最大滚动尝试: {max_scroll}次")
        print("当连续检测不到变化时，程序会暂停检测，按Enter键恢复...")
        print("=" * 50)
        
        monitor_and_click_optimized(saved_x, saved_y, check_interval=interval, max_scroll_attempts=max_scroll)
        
        # 监控结束后询问是否继续
        continue_choice = input("\n监控已停止，是否返回主菜单？(y/n): ")
        if continue_choice.lower() != 'y':
            print("退出程序")
            break