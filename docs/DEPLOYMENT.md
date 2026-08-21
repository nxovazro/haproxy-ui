# Roxy-WI 公网部署指南

本文档提供 Roxy-WI 的生产环境部署指南，包括 HTTPS 反向代理配置。

## 目录

1. [系统要求](#系统要求)
2. [Nginx HTTPS 反代配置](#nginx-https-反代配置)
3. [Apache HTTPS 反代配置](#apache-https-反代配置)
4. [HAProxy HTTPS 反代配置](#haproxy-https-反代配置)
5. [SSL 证书获取](#ssl-证书获取)
6. [Systemd 服务配置](#systemd-服务配置)
7. [安全建议](#安全建议)
8. [监控和日志](#监控和日志)

---

## 系统要求

- **操作系统**: Ubuntu 20.04+, CentOS 8+, Debian 11+
- **Python**: 3.8 或更高版本
- **内存**: 最少 2GB（推荐 4GB）
- **磁盘**: 最少 10GB（推荐 20GB）
- **反向代理**: Nginx、Apache 或 HAProxy
- **数据库**: MySQL 5.7+、MariaDB 10.3+ 或 SQLite（仅用于开发）

### 系统依赖安装

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    python3.10 \
    python3.10-venv \
    python3.10-dev \
    python3-pip \
    curl \
    wget \
    git \
    nginx \
    mysql-server \
    ssl-cert
```

**CentOS/RHEL:**
```bash
sudo yum install -y \
    python3.10 \
    python3.10-devel \
    git \
    nginx \
    mysql-server \
    curl \
    wget
```

---

## Nginx HTTPS 反代配置

### 1. 安装 Nginx

```bash
sudo apt-get install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

### 2. 获取 SSL 证书（使用 Let's Encrypt）

```bash
# 安装 Certbot
sudo apt-get install -y certbot python3-certbot-nginx

# 获取证书（替换 your-domain.com）
sudo certbot certonly --standalone -d your-domain.com -d www.your-domain.com
```

证书位置：
- 证书文件: `/etc/letsencrypt/live/your-domain.com/fullchain.pem`
- 私钥文件: `/etc/letsencrypt/live/your-domain.com/privkey.pem`

### 3. 创建 Nginx 配置文件

```bash
sudo nano /etc/nginx/sites-available/roxy-wi
```

配置内容（适用于 Gunicorn 后端）：

```nginx
# HTTP 重定向到 HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name your-domain.com www.your-domain.com;

    # Let's Encrypt 验证
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 其他请求重定向到 HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS 主配置
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name your-domain.com www.your-domain.com;

    # SSL 证书配置
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/your-domain.com/chain.pem;

    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 日志
    access_log /var/log/nginx/roxy-wi-access.log;
    error_log /var/log/nginx/roxy-wi-error.log;

    # 上传限制
    client_max_body_size 16M;

    # 代理到 Gunicorn（本地 8000 端口）
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $server_name;
        proxy_read_timeout 120s;
        proxy_connect_timeout 120s;
    }

    # 静态文件（如果有）
    location /static/ {
        alias /var/www/haproxy-ui/app/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
```

### 4. 启用配置

```bash
# 创建软链接
sudo ln -s /etc/nginx/sites-available/roxy-wi /etc/nginx/sites-enabled/

# 检查配置语法
sudo nginx -t

# 重启 Nginx
sudo systemctl restart nginx
```

### 5. 配置证书自动续期

```bash
# 编辑 crontab
sudo crontab -e

# 添加以下行（每月检查一次）
0 3 1 * * certbot renew --quiet && systemctl reload nginx
```

---

## Apache HTTPS 反代配置

### 1. 安装 Apache 和必要模块

```bash
sudo apt-get install -y apache2 certbot python3-certbot-apache

# 启用代理模块
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod ssl
sudo a2enmod rewrite
sudo a2enmod headers
```

### 2. 获取 SSL 证书

```bash
sudo certbot certonly --standalone -d your-domain.com -d www.your-domain.com
```

### 3. 创建 Apache 虚拟主机配置

```bash
sudo nano /etc/apache2/sites-available/roxy-wi.conf
```

配置内容：

```apache
# HTTP 重定向到 HTTPS
<VirtualHost *:80>
    ServerName your-domain.com
    ServerAlias www.your-domain.com
    
    # Let's Encrypt 验证目录
    DocumentRoot /var/www/certbot
    
    <Directory /var/www/certbot>
        Require all granted
    </Directory>

    # 其他请求重定向到 HTTPS
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/.well-known/acme-challenge
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>

# HTTPS 主配置
<VirtualHost *:443>
    ServerName your-domain.com
    ServerAlias www.your-domain.com

    # SSL 证书配置
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/your-domain.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/your-domain.com/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/your-domain.com/chain.pem

    # SSL 安全配置
    SSLProtocol -All +TLSv1.2 +TLSv1.3
    SSLCipherSuite HIGH:!aNULL:!MD5
    SSLHonorCipherOrder on
    SSLSessionCache shmcb:/var/run/apache2/ssl_scache(512000)
    SSLSessionTimeout 300

    # 安全头
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"

    # 日志
    ErrorLog ${APACHE_LOG_DIR}/roxy-wi-error.log
    CustomLog ${APACHE_LOG_DIR}/roxy-wi-access.log combined

    # 上传限制
    LimitRequestBody 16777216

    # 反向代理配置
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    # 代理头配置
    <Location />
        ProxyPassReverse /
        RequestHeader set X-Forwarded-Proto "https"
        RequestHeader set X-Forwarded-Host "%{HTTP_HOST}e"
        RequestHeader set X-Forwarded-For "%{REMOTE_ADDR}e"
    </Location>

    # 静态文件缓存（如果有）
    <Directory /var/www/haproxy-ui/app/static>
        Require all granted
        ExpiresActive On
        ExpiresDefault "access plus 30 days"
    </Directory>
</VirtualHost>
```

### 4. 启用配置

```bash
# 启用虚拟主机
sudo a2ensite roxy-wi

# 禁用默认站点
sudo a2dissite 000-default

# 检查配置语法
sudo apache2ctl configtest

# 重启 Apache
sudo systemctl restart apache2
```

---

## HAProxy HTTPS 反代配置

### 1. 安装 HAProxy

```bash
sudo apt-get install -y haproxy

# 或从源代码编译最新版本
```

### 2. 准备 SSL 证书（PEM 格式）

```bash
# 从 Let's Encrypt 证书生成 PEM
sudo cat /etc/letsencrypt/live/your-domain.com/fullchain.pem \
    /etc/letsencrypt/live/your-domain.com/privkey.pem > \
    /etc/ssl/certs/haproxy-bundle.pem

sudo chmod 600 /etc/ssl/certs/haproxy-bundle.pem
```

### 3. 创建 HAProxy 配置

编辑 `/etc/haproxy/haproxy.cfg`：

```haproxy
global
    log stdout local0
    log stdout local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # 默认 SSL 材料位置
    ca-base /etc/ssl/certs
    crl-base /etc/ssl/private

    # SSL 性能
    tune.ssl.default-dh-param 2048
    tune.ssl.protocols TLSv1.2 TLSv1.3
    tune.ssl.ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

# 统计页面
listen stats
    bind 127.0.0.1:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

# HTTP 到 HTTPS 的重定向
frontend http-in
    bind *:80
    mode http
    
    # Let's Encrypt 验证
    acl letsencrypt path_beg /.well-known/acme-challenge/
    use_backend certbot if letsencrypt
    
    # 重定向到 HTTPS
    redirect scheme https code 301 if !letsencrypt

# HTTPS 前端
frontend https-in
    bind *:443 ssl crt /etc/ssl/certs/haproxy-bundle.pem \
        ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256 \
        options ssl-default-bind-options no-tls-tickets
    
    mode http
    option httplog
    option forwardfor

    # 安全头
    http-response add-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response add-header X-Frame-Options "SAMEORIGIN"
    http-response add-header X-Content-Type-Options "nosniff"
    http-response add-header X-XSS-Protection "1; mode=block"

    # 转到后端
    default_backend roxy-wi-backend

# Certbot 验证后端
backend certbot
    mode http
    server certbot 127.0.0.1:8888

# Roxy-WI 后端
backend roxy-wi-backend
    mode http
    balance roundrobin
    option forwardfor
    option httpchk GET / HTTP/1.1\r\nHost:\ your-domain.com
    
    # 粘性会话（可选）
    cookie SERVERID insert indirect nocache
    
    server roxy-wi-01 127.0.0.1:8000 check inter 10000 fall 3 rise 2 cookie s1
    
    # 如果有多个 Roxy-WI 实例，添加更多行：
    # server roxy-wi-02 127.0.0.1:8001 check inter 10000 fall 3 rise 2 cookie s2
```

### 4. 启动 HAProxy

```bash
# 检查配置
sudo haproxy -f /etc/haproxy/haproxy.cfg -c

# 启动服务
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# 访问统计页面
# http://localhost:8404/stats
```

---

## SSL 证书获取

### 选项 1：Let's Encrypt（免费，推荐）

```bash
# 安装 Certbot
sudo apt-get install -y certbot python3-certbot-{nginx,apache}

# 获取证书
sudo certbot certonly --standalone -d your-domain.com

# 证书路径
# /etc/letsencrypt/live/your-domain.com/
```

### 选项 2：自签名证书（仅用于测试）

```bash
# 生成自签名证书（有效期 365 天）
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/roxy-wi.key \
    -out /etc/ssl/certs/roxy-wi.crt
```

### 选项 3：商业 SSL 证书

从 Comodo、DigiCert 等商业提供商购买，按照提供商说明配置。

---

## Systemd 服务配置

### 创建 Roxy-WI 服务文件

```bash
sudo nano /etc/systemd/system/roxy-wi.service
```

内容：

```ini
[Unit]
Description=Roxy-WI Web Interface
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=notify
User=roxy-wi
Group=roxy-wi
WorkingDirectory=/var/www/haproxy-ui

# 环境变量
Environment="ROXYWI_CONFIG=/etc/roxy-wi/roxy-wi.cfg"
Environment="ROXYWI_LOG_PATH=/var/log/roxy-wi"

# 启动命令
ExecStart=/var/www/haproxy-ui/venv/bin/gunicorn \
    --workers=4 \
    --threads=2 \
    --bind=unix:/var/run/roxy-wi/roxy-wi.sock \
    --access-logfile=/var/log/roxy-wi/access.log \
    --error-logfile=/var/log/roxy-wi/error.log \
    --log-level=info \
    'app:app'

# 重启策略
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# 资源限制
LimitNOFILE=65535
LimitNPROC=65535

[Install]
WantedBy=multi-user.target
```

### 启用和启动服务

```bash
# 创建用户和目录
sudo useradd -r -s /bin/bash roxy-wi
sudo mkdir -p /var/log/roxy-wi /var/run/roxy-wi
sudo chown -R roxy-wi:roxy-wi /var/log/roxy-wi /var/run/roxy-wi /var/www/haproxy-ui

# 重新加载 systemd
sudo systemctl daemon-reload

# 启用并启动服务
sudo systemctl enable roxy-wi
sudo systemctl start roxy-wi

# 检查状态
sudo systemctl status roxy-wi

# 查看日志
sudo journalctl -u roxy-wi -f
```

---

## 安全建议

### 1. 防火墙配置

```bash
# 使用 ufw（Ubuntu）
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw enable

# 或使用 firewalld（CentOS）
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload
```

### 2. 应用安全配置

编辑 `/etc/roxy-wi/roxy-wi.cfg`：

```ini
[main]
# 使用强密钥
secret_phrase = YOUR_STRONG_RANDOM_KEY_HERE

[mysql]
# 使用强密码
mysql_password = YOUR_STRONG_DB_PASSWORD
```

### 3. 数据库安全

```bash
# MySQL 安全初始化
sudo mysql_secure_installation

# 创建专用数据库用户
mysql -u root -p << 'EOF'
CREATE DATABASE roxywi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'roxy-wi'@'localhost' IDENTIFIED BY 'strong_password';
GRANT ALL PRIVILEGES ON roxywi.* TO 'roxy-wi'@'localhost';
FLUSH PRIVILEGES;
EOF
```

### 4. 定期更新

```bash
# 系统更新
sudo apt-get update && sudo apt-get upgrade -y

# Python 包更新
pip install --upgrade -r requirements.txt

# 检查安全漏洞
pip audit
```

### 5. 访问控制

如果需要限制访问，在反代中添加：

**Nginx:**
```nginx
location / {
    # 允许特定 IP
    allow 192.168.1.0/24;
    allow 10.0.0.0/8;
    deny all;
    
    proxy_pass http://127.0.0.1:8000;
}
```

**Apache:**
```apache
<Location />
    Require ip 192.168.1.0/24 10.0.0.0/8
</Location>
```

---

## 监控和日志

### 1. 查看应用日志

```bash
# Systemd 日志
sudo journalctl -u roxy-wi -f

# 应用日志
tail -f /var/log/roxy-wi/roxy-wi.log

# 访问日志
tail -f /var/log/roxy-wi/access.log
```

### 2. Nginx 日志

```bash
# 实时查看
sudo tail -f /var/log/nginx/roxy-wi-access.log
sudo tail -f /var/log/nginx/roxy-wi-error.log

# 分析
sudo zcat /var/log/nginx/roxy-wi-access.log* | \
    awk '{print $1}' | sort | uniq -c | sort -rn
```

### 3. 监控系统资源

```bash
# 实时监控
top -p $(pgrep -f gunicorn | tr '\n' ',' | sed 's/,$//')

# 或使用 htop
sudo apt-get install htop
htop -p $(pgrep -f gunicorn)
```

### 4. 证书过期提醒

```bash
# 查看证书有效期
sudo certbot certificates

# 手动续期
sudo certbot renew --dry-run  # 测试
sudo certbot renew            # 实际续期
```

---

## 故障排除

### 问题 1：反代连接失败

```bash
# 检查后端是否运行
sudo systemctl status roxy-wi

# 检查端口监听
sudo netstat -tulpn | grep gunicorn

# 查看反代日志
sudo tail -f /var/log/nginx/roxy-wi-error.log
```

### 问题 2：SSL 证书错误

```bash
# 检查证书有效性
sudo openssl x509 -in /etc/letsencrypt/live/your-domain.com/fullchain.pem -text -noout

# 测试 SSL 连接
openssl s_client -connect your-domain.com:443
```

### 问题 3：性能问题

```bash
# 增加 Gunicorn 工作进程数
# 在 systemd 服务中修改 --workers 参数

# 检查数据库连接
mysql -u roxy-wi -p roxywi -e "SHOW PROCESSLIST;"

# 查看应用性能
sudo systemctl status roxy-wi
```

---

## 生产清单

- ✅ 获取有效的 SSL 证书（Let's Encrypt）
- ✅ 配置反向代理（Nginx/Apache/HAProxy）
- ✅ 设置 Systemd 服务
- ✅ 配置数据库（MySQL/MariaDB）
- ✅ 配置防火墙
- ✅ 设置日志轮转
- ✅ 配置备份策略
- ✅ 设置监控告警
- ✅ 创建用户账户和权限
- ✅ 文档记录部署信息

---

## 相关链接

- [Let's Encrypt 官网](https://letsencrypt.org/)
- [Nginx 反向代理文档](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [Apache mod_proxy 文档](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html)
- [HAProxy 官方文档](http://www.haproxy.org/#docs)
- [Roxy-WI 官网](https://roxy-wi.org/)
