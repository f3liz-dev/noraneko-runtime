# SPDX-License-Identifier: MPL-2.0

echo Before:
free -h
df -h

echo
echo

# remove swap because current github actions have 16GB RAM, and it's same as taskcluster's RAM
#sudo swapoff /mnt/swapfile
#sudo rm /mnt/swapfile
#sudo fallocate -l 30G /mnt/swapfile
#sudo chmod 600 /mnt/swapfile
#sudo mkswap /mnt/swapfile
#sudo swapon /mnt/swapfile

sudo apt autoremove -y
sudo apt clean
sudo rm -rf  ./git
sudo rm -rf /home/linuxbrew
sudo rm -rf /usr/share/dotnet
sudo rm -rf /usr/local/lib/android
sudo rm -rf /usr/local/graalvm
sudo rm -rf /usr/local/share/powershell
sudo rm -rf /usr/local/share/chromium
sudo rm -rf /opt/ghc
sudo rm -rf /usr/local/share/boost
sudo rm -rf /etc/apache2
sudo rm -rf /etc/nginx
sudo rm -rf /usr/local/share/chrome_driver
sudo rm -rf /usr/local/share/edge_driver
sudo rm -rf /usr/local/share/gecko_driver
sudo rm -rf /usr/share/java
sudo rm -rf /usr/share/miniconda
sudo rm -rf /usr/local/share/vcpkg


echo
echo

echo After:
free -h
df -h
