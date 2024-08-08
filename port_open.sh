#!/bin/bash
# Устанавливаем обновления
apt-get update -y

# Устанавливаем nginx
apt-get install -y nginx
apt-get install -y bash-completion 

apt-get install -y fcgiwrap

# Создаем скрипт для отображения открытых портов
cat <<'EOF' > /etc/nginx/port_open.sh
#!/bin/bash
echo "Content-type: text/html"
echo ""
echo "<h1>Fedorov M.V. </h>"
echo '<h1><atarget="_blank"> https://github.com/Mifakcen/test-selectel/tree/main </a></h1>'
echo "<html><body><pre>"
ss -tuln
echo "</pre></body></html>"
EOF

chmod +x /etc/nginx/port_open.sh

cat <<'EOF' > /etc/nginx/sites-available/default

server {
	listen 80 default_server;
	listen [::]:80 default_server;
	root /var/www/html;
	index index.html index.htm index.nginx-debian.html;
	server_name _;
	location / {
		include /etc/nginx/fastcgi_params;
		fastcgi_param SCRIPT_FILENAME /etc/nginx/port_open.sh;
		fastcgi_pass unix:/var/run/fcgiwrap.socket;
		try_files $uri $uri/ =404;
	}
}
EOF

# Перезапускаем nginx
systemctl restart nginx
systemctl enable nginx
