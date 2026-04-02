#!/usr/bin/env python3
# ============================================================================
# setup-pbr-debian.py — 多网卡 / 多出口 VM 一键策略路由配置脚本 (Debian 12 原生版)
#
# 功能：
#   1. 解析 Debian 传统的 /etc/network/interfaces 或 interfaces.d/ 配置
#   2. 自动提取多网卡的静态 IP 和网关
#   3. 为主路由表自动分配 metric（防止多网关冲突）
#   4. 自动在配置中注入 post-up / pre-down 策略路由规则 (PBR)
#   5. 禁用 cloud-init 网络接管，并生成新的安全配置
#
# 依赖：Python 3 (纯内置库，无需安装任何额外依赖)
# 适用：Debian 12 (ifupdown / /etc/network/interfaces)
# ============================================================================

import argparse
import ipaddress
import os
import shutil
import subprocess
import sys
from datetime import datetime

# ── 颜色输出 ──────────────────────────────────────────────────────────────────

class Log:
    RED    = "\033[0;31m"
    GREEN  = "\033[0;32m"
    YELLOW = "\033[1;33m"
    CYAN   = "\033[0;36m"
    NC     = "\033[0m"

    @staticmethod
    def info(msg: str): print(f"{Log.CYAN}[INFO]{Log.NC}  {msg}")
    @staticmethod
    def ok(msg: str):   print(f"{Log.GREEN}[ OK ]{Log.NC}  {msg}")
    @staticmethod
    def warn(msg: str): print(f"{Log.YELLOW}[WARN]{Log.NC}  {msg}")
    @staticmethod
    def err(msg: str):  print(f"{Log.RED}[ERR]{Log.NC}   {msg}", file=sys.stderr)

# ── 解析器模型 ────────────────────────────────────────────────────────────────

class GenericLine:
    def __init__(self, line: str):
        self.line = line
    def render(self, metrics=None, tables=None) -> str:
        return self.line

class IfaceBlock:
    def __init__(self, decl_line: str):
        self.decl = decl_line
        parts = decl_line.strip().split()
        self.name = parts[1] if len(parts) > 1 else ""
        self.family = parts[2] if len(parts) > 2 else ""  # inet, inet6
        self.method = parts[3] if len(parts) > 3 else ""  # static, dhcp
        self.lines = []
        self.addresses = []
        self.gateway = None

    def add_line(self, line: str):
        s = line.strip()
        # 【幂等性处理】过滤掉以前脚本可能注入的 metric 和 pbr 规则
        if s.startswith("metric "): return
        if ("post-up ip" in s or "pre-down ip" in s) and " table " in s: return

        self.lines.append(line)

        # 提取配置
        if s.startswith("address "):
            self.addresses.append(s.split(" ")[1])
        elif s.startswith("gateway "):
            self.gateway = s.split(" ")[1]

    def render(self, metrics=None, tables=None) -> str:
        out = [self.decl]
        out.extend(self.lines)

        # 仅对存在静态网关的接口注入 PBR
        if self.gateway and self.method == "static" and metrics and self.name in metrics:
            metric = metrics[self.name]
            table_id = tables[self.name]
            is_ipv6 = (self.family == "inet6")
            ip_cmd = "ip -6" if is_ipv6 else "ip"
            indent = "    "
            
            out.append(f"{indent}# --- Auto-generated PBR Rules ---\n")
            out.append(f"{indent}metric {metric}\n")
            
            # 路由表默认路由
            out.append(f"{indent}post-up {ip_cmd} route add default via {self.gateway} table {table_id} || true\n")
            
            # 为每个绑定的 IP 添加策略匹配
            for addr in self.addresses:
                try:
                    ip = str(ipaddress.ip_interface(addr).ip)
                except ValueError:
                    ip = addr.split('/')[0] # 降级处理
                
                out.append(f"{indent}post-up {ip_cmd} rule add from {ip} table {table_id}\n")
                out.append(f"{indent}pre-down {ip_cmd} rule del from {ip} table {table_id} || true\n")
                
            out.append(f"{indent}# --------------------------------\n")
            
        return "".join(out)

# ── 核心逻辑 ──────────────────────────────────────────────────────────────────

def parse_eni(filepath: str):
    """解析 Debian 的 interfaces 配置文件"""
    blocks = []
    current_iface = None
    
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("iface "):
                if current_iface: blocks.append(current_iface)
                current_iface = IfaceBlock(line)
            elif s.startswith(("auto ", "allow-hotplug ", "source ", "source-directory ", "mapping ")):
                if current_iface:
                    blocks.append(current_iface)
                    current_iface = None
                blocks.append(GenericLine(line))
            elif not s or s.startswith("#"):
                if current_iface: current_iface.add_line(line)
                else: blocks.append(GenericLine(line))
            else:
                if current_iface: current_iface.add_line(line)
                else: blocks.append(GenericLine(line))
                
    if current_iface: blocks.append(current_iface)
    return blocks

def disable_cloud_init_network():
    """彻底禁用 cloud-init 网络接管，防止重启覆盖"""
    cloud_cfg = "/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
    if os.path.exists("/etc/cloud"):
        with open(cloud_cfg, "w", encoding="utf-8") as f:
            f.write("network: {config: disabled}\n")
        Log.ok("已配置 Cloud-Init 禁用网络接管 (防止重启后丢失配置)")

# ── 主程序 ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Debian 12 原生多网卡策略路由配置 (ifupdown)")
    parser.add_argument("config", nargs="?", default="", help="指定配置文件路径")
    parser.add_argument("--dry-run", action="store_true", help="仅预览生成的内容")
    args = parser.parse_args()

    # 如果用户没有指定，则智能探测是标准 interfaces 还是 cloud-init 配置
    target_file = args.config
    if not target_file:
        if os.path.exists("/etc/network/interfaces.d/50-cloud-init"):
            target_file = "/etc/network/interfaces.d/50-cloud-init"
        else:
            target_file = "/etc/network/interfaces"

    if not args.dry_run and os.geteuid() != 0:
        Log.err("必须使用 root 权限执行此脚本 (sudo)")
        sys.exit(1)

    if not os.path.isfile(target_file):
        Log.err(f"找不到配置文件: {target_file}")
        sys.exit(1)

    Log.info(f"正在读取网卡配置: {target_file}")
    blocks = parse_eni(target_file)

    # 提取所有包含静态网关的接口名
    routed_ifaces = []
    has_dhcp = False
    for b in blocks:
        if isinstance(b, IfaceBlock):
            if b.method in ("dhcp", "auto"):
                has_dhcp = True
            if b.method == "static" and b.gateway:
                if b.name not in routed_ifaces:
                    routed_ifaces.append(b.name)

    if has_dhcp:
        Log.warn("检测到有网卡使用 DHCP。PBR 策略路由通常要求配置为静态 IP 和网关，动态网卡会被忽略。")

    if len(routed_ifaces) < 2:
        Log.warn(f"仅发现 {len(routed_ifaces)} 个配置了静态网关的主接口。多网卡 PBR 通常需要 >= 2 个。")
        if len(routed_ifaces) == 0:
            Log.err("没有提取到可配置的静态网关信息，脚本退出。")
            sys.exit(1)

    # 分配优先级 (Metrics) 和 路由表号 (Table ID)
    # 例如：eth0 优先级更高，metric=100, table=100；eth1 metric=110, table=110
    metrics = {}
    tables = {}
    for i, name in enumerate(routed_ifaces):
        metrics[name] = 100 + (i * 10)
        tables[name] = 100 + (i * 10)
        Log.info(f"接口 {name:<6s} -> 分配 Metric={metrics[name]}, 路由表={tables[name]}")

    # 渲染新配置
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    output_lines = [
        f"# 修改自 setup-pbr-debian.py · {now}\n",
        "# PBR (策略路由) 规则已自动注入。\n\n"
    ]
    for b in blocks:
        output_lines.append(b.render(metrics, tables))
        
    new_config_content = "".join(output_lines)

    if args.dry_run:
        print()
        Log.info(f"===== 预览生成的配置 {target_file} =====")
        print(new_config_content)
        return

    # 应用写入
    backup_file = f"{target_file}.bak"
    shutil.copy2(target_file, backup_file)
    Log.ok(f"原配置文件已备份至: {backup_file}")

    disable_cloud_init_network()

    with open(target_file, "w", encoding="utf-8") as f:
        f.write(new_config_content)
    Log.ok(f"已成功注入策略路由配置到: {target_file}")

    # 重启网络提示
    print()
    Log.warn("配置文件已修改完成。要使配置生效，你需要重启网络服务。")
    Log.warn("注意：如果你正通过 SSH 连接，重启网络期间可能会发生短暂断开。")
    print()
    try:
        confirm = input(f"{Log.YELLOW}是否立即执行 systemctl restart networking？[y/N]: {Log.NC}").strip().lower()
    except (EOFError, KeyboardInterrupt):
        confirm = "n"
        print()

    if confirm == "y":
        Log.info("正在重启 networking 服务...")
        res = subprocess.run(["systemctl", "restart", "networking"], check=False)
        if res.returncode == 0:
            Log.ok("网络服务重启成功！PBR 策略已生效。")
            print()
            Log.info("你可以使用以下命令检查验证：")
            print("    ip rule show             # 查看是否成功匹配了网卡独立 IP")
            print("    ip route show table 100  # 查看自定义路由表 100 (首个网卡)")
        else:
            Log.err("网络服务重启失败，请检查配置文件格式。")
            print(f"如需恢复原状，请执行：mv {backup_file} {target_file} && systemctl restart networking")
    else:
        Log.info("已跳过重启。稍后请手动执行: sudo systemctl restart networking")

if __name__ == "__main__":
    main()
