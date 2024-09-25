1.Create script of below command
vi /home/ubuntu/start-stopped-containers.sh
#!/bin/bash
docker start $(docker ps -a -q -f status=exited)

2.then create service file
sudo vi /etc/systemd/system/start-stopped-containers.service 

[Unit]
Description=Start stopped Docker containers after boot
After=docker.service
Requires=docker.service

[Service]
ExecStart=/bin/bash /home/ubuntu/start-stopped-containers.sh
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Restart=always

[Install]
WantedBy=multi-user.target

3.start,enable & reload the daemon
sudo systemctl enable start-stopped-containers.service
sudo systemctl start start-stopped-containers.service
sudo systemctl daemon-reload


