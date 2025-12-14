read -p "Enter hostlist: " victim
read -p "Enter the IP of the jVision Server: " jvis
nmap -sn -iL "$victim" -oG - | awk '/Up$/{print $2}' > aqua_hosts.txt
nmap -T5 -iL aqua_hosts.txt --top-ports 10000 --exclude-ports 502 -oX scan.xml
read -p "hit enter to continue (make sure jvis is up)..." confirm
wget https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_linux_amd64_1.7.0.zip -O aquatone.zip
mkdir aqua
unzip aquatone.zip
cat scan.xml | ./aquatone -out aqua -nmap
cd aqua
zip -r ../aquatonereport.zip *
cd ..
curl -i -X POST -H "Content-Type: multipart/form-data" -F 'data=@aquatonereport.zip' http://"$jvis":7777/upload
