#!/usr/bin/env python3
"""把宝塔（nyh-prod）的 nginx 站点配置转写成 Debian nginx 可用的配置。

用法：
    convert-baota-nginx.py <宝塔导出目录> <输出目录>

宝塔导出目录结构（从旧机 rsync 下来）：
    nginx/      = /www/server/panel/vhost/nginx/
    rewrite/    = /www/server/panel/vhost/rewrite/
    main/       = /www/server/nginx/conf/ 里的 nginx.conf、proxy.conf、fastcgi.conf、pathinfo.conf

输出目录对应服务器上的 /etc/nginx/nyh/：
    vhost/<站点>.conf    站点配置
    extension/<站点>/    宝塔 extension 目录，去掉 site_total.conf
    rewrite/<站点>.conf  伪静态规则，原样
    snippets/            enable-php-XX.conf、fastcgi.conf、pathinfo.conf、acme.conf
    http.conf            http 级公共配置（来自宝塔 nginx.conf 的 http 块 + proxy.conf）
证书不在这里处理：服务器上 /etc/nginx/nyh/cert/<站点>/ 直接从旧机拷。

只做固定替换，不改业务逻辑；改了什么都在下面 REPLACEMENTS / SKIP 里写清楚。
"""
import re
import shutil
import sys
from pathlib import Path

NYH = "/etc/nginx/nyh"

# 宝塔自用、新机不需要的站点配置文件
SKIP_VHOSTS = {
    "0.site_total_log_format.conf",  # 宝塔流量统计的日志格式
    "waf2monitor_data.conf",         # 宝塔 WAF
    "phpfpm_status.conf",            # 宝塔面板读 FPM 状态
    "0.fastcgi_cache.conf",          # 没有站点用 fastcgi_cache
    # 已停用站点（root 已是 /www/server/stop），不再建 vhost
    "fa.nanyahui.com.conf",
    "yysg.nanyahui.com.conf",
    "test-agent.nanyahui.cn.conf",
}

# 固定路径替换（顺序有关）
REPLACEMENTS = [
    ("/www/server/panel/vhost/nginx/well-known/", f"{NYH}/well-known/"),
    ("/www/server/panel/vhost/nginx/extension/", f"{NYH}/extension/"),
    ("/www/server/panel/vhost/rewrite/", f"{NYH}/rewrite/"),
    ("/www/server/panel/vhost/cert/", f"{NYH}/cert/"),
    ("/www/server/nginx/html", "/var/www/html"),
]

PHP_INCLUDE = re.compile(r"include\s+enable-php-(\d+)\.conf;")

# PHP 版本 → 容器里的 FPM 端口（见 nyh-prod-2026/docker/php/compose.yaml）
PHP_PORTS = {"74": 9074, "82": 9082}


def convert_vhost(text: str) -> str:
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    text = PHP_INCLUDE.sub(lambda m: f"include {NYH}/snippets/enable-php-{m.group(1)}.conf;", text)
    # 宝塔的 well-known 引用改成统一的 ACME snippet（原文件用 lua，Debian nginx 没有 lua）
    text = re.sub(
        rf"include {re.escape(NYH)}/well-known/[^;]+;",
        f"include {NYH}/snippets/acme.conf;",
        text,
    )
    return text


def write_snippets(main_dir: Path, out: Path) -> None:
    snip = out / "snippets"
    snip.mkdir(parents=True, exist_ok=True)
    for name in ("fastcgi.conf", "pathinfo.conf"):
        shutil.copy(main_dir / name, snip / name)
    for ver, port in PHP_PORTS.items():
        (snip / f"enable-php-{ver}.conf").write_text(
            f"# 宝塔 enable-php-{ver}.conf 的等价物；FPM 跑在容器 php{ver}-fpm 里（host 网络）\n"
            "location ~ [^/]\\.php(/|$)\n"
            "{\n"
            "    try_files $uri =404;\n"
            f"    fastcgi_pass  127.0.0.1:{port};\n"
            "    fastcgi_index index.php;\n"
            f"    include {NYH}/snippets/fastcgi.conf;\n"
            f"    include {NYH}/snippets/pathinfo.conf;\n"
            "}\n"
        )
    # enable-php-00 在宝塔里是空文件（纯静态站点）
    (snip / "enable-php-00.conf").write_text("# 纯静态站点，不处理 PHP（宝塔 enable-php-00.conf 本来就是空的）\n")
    (snip / "acme.conf").write_text(
        "# Let's Encrypt HTTP-01 验证目录（certbot --webroot -w /var/www/letsencrypt）\n"
        "# 替代宝塔 well-known/*.conf 里的 lua 实现\n"
        "location ^~ /.well-known/acme-challenge/ {\n"
        "    root /var/www/letsencrypt;\n"
        "    default_type text/plain;\n"
        "    try_files $uri =404;\n"
        "}\n"
    )


HTTP_CONF = """# http 级公共配置。值逐条照搬宝塔 /www/server/nginx/conf/nginx.conf 的 http 块与 proxy.conf
# （2026-11-10 导出）；去掉了 lua_package_path、宝塔自带的 phpMyAdmin :888 server 块。
# 由 scripts/convert-baota-nginx.py 生成。
server_names_hash_bucket_size 512;
client_header_buffer_size 32k;
large_client_header_buffers 4 32k;
client_max_body_size 50m;
sendfile   on;
tcp_nopush on;
keepalive_timeout 60;
tcp_nodelay on;

fastcgi_connect_timeout 300;
fastcgi_send_timeout 300;
fastcgi_read_timeout 300;
fastcgi_buffer_size 64k;
fastcgi_buffers 4 64k;
fastcgi_busy_buffers_size 128k;
fastcgi_temp_file_write_size 256k;
fastcgi_intercept_errors on;

gzip on;
gzip_min_length  1k;
gzip_buffers     4 16k;
gzip_http_version 1.1;
gzip_comp_level 5;
gzip_types     text/plain application/javascript application/x-javascript text/javascript text/css application/xml application/json image/jpeg image/gif image/png font/ttf font/otf image/svg+xml application/xml+rss text/x-js;
gzip_vary on;
gzip_proxied   expired no-cache no-store private auth;
gzip_disable   "MSIE [1-6]\\.";

limit_conn_zone $binary_remote_addr zone=perip:10m;
limit_conn_zone $server_name zone=perserver:10m;
limit_req_zone $binary_remote_addr zone=yunshu_login:10m rate=5r/m;

server_tokens off;
access_log off;

map $scheme $hsts_header {
    https "max-age=63072000; includeSubDomains; preload";
    default "";
}

# --- 宝塔 proxy.conf（全局开着 proxy_cache，保持一致） ---
proxy_temp_path /var/cache/nginx/proxy_temp;
proxy_cache_path /var/cache/nginx/proxy_cache levels=1:2 keys_zone=cache_one:20m inactive=1d max_size=5g;
client_body_buffer_size 512k;
proxy_connect_timeout 60;
proxy_read_timeout 60;
proxy_send_timeout 60;
proxy_buffer_size 32k;
proxy_buffers 4 64k;
proxy_busy_buffers_size 128k;
proxy_temp_file_write_size 128k;
proxy_next_upstream error timeout invalid_header http_500 http_503 http_404;
proxy_cache cache_one;
"""


def write_http_conf(out: Path) -> None:
    (out / "http.conf").write_text(HTTP_CONF)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    if out.exists():
        shutil.rmtree(out)
    (out / "vhost").mkdir(parents=True)

    converted = []
    for f in sorted((src / "nginx").glob("*.conf")):
        if f.name in SKIP_VHOSTS:
            continue
        (out / "vhost" / f.name).write_text(convert_vhost(f.read_text()))
        converted.append(f.name)

    for d in sorted((src / "nginx" / "extension").iterdir()):
        if not d.is_dir():
            continue
        target = out / "extension" / d.name
        target.mkdir(parents=True)
        for f in d.glob("*.conf"):
            if f.name != "site_total.conf":
                (target / f.name).write_text(convert_vhost(f.read_text()))

    (out / "rewrite").mkdir()
    for f in sorted((src / "rewrite").glob("*.conf")):
        shutil.copy(f, out / "rewrite" / f.name)

    write_snippets(src / "main", out)
    write_http_conf(out)

    leftovers = [
        f"{p.relative_to(out)}: {line.strip()}"
        for p in out.rglob("*.conf")
        for line in p.read_text().splitlines()
        if re.search(r"/www/server/|lua|site_total|waf", line)
        and "lua|ts|go" not in line  # 宝塔禁止在 .well-known 放敏感文件的规则，里面的 lua 是扩展名
        and not line.strip().startswith("#")
    ]
    print(f"转写站点 {len(converted)} 个：{', '.join(converted)}")
    if leftovers:
        print("仍含宝塔路径或指令，需人工检查：")
        print("\n".join(leftovers))
    return 0


if __name__ == "__main__":
    sys.exit(main())
