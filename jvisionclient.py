import argparse
import sys
import os
import requests
import time
from pwn import *
from bs4 import BeautifulSoup
import json

#LOOP
#ADD LESS COMPLEX SCAN

class Color:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    END = '\033[0m'


class Beautifier:
    def __init__(self, f, ts, s):
        self.f = open(f, 'rb')
        self.target_server = ts
        self.json_object = []
        self.subnet = s
        
    def parse_scan(self):
        try:
            soup = BeautifulSoup(self.f, "xml")
        except Exception as e:
            print(e)
            return
        try:
            hosts = soup.find_all('host')
        except Exception as e:
            print(e)
            return
        if hosts:
            for host in hosts:
                json_host = {}
                json_services = []
                try:
                    json_host['ip'] = host.address.get('addr')
                except:
                    json_host['ip'] = None
                try:
                    json_host['state'] = host.status.get('state')
                except:
                    json_host['state'] = None
                try:
                    json_host['hostname'] = host.hostname.get('name')
                except:
                    json_host['hostname'] = None
                try:
                    json_host['subnet'] = self.subnet
                except:
                    json_host['subnet'] = None


                try:
                    ports = host.find_all('port')
                except:
                    ports = None

                if ports:
                    for p in ports:
                        json_port = {}
                        try:
                            json_port['port'] = p.get('portid')
                        except:
                            json_port['port'] = None
                        try:
                            json_port['protocol'] = p.get('protocol')
                        except:
                            json_port['protocol'] = None
                        try:
                            json_port['state'] = p.state.get('state')
                        except:
                            json_port['state'] = None
                        try:
                            json_port['name'] = p.service.get('name')
                        except:
                            json_port['name'] = None
                        try:
                            json_port['version']  =  p.service.get('version')
                        except:
                            json_port['version']  = None
                        try:
                            json_port['script'] = p.script.get('output')
                        except:
                            json_port['script'] = None
                        json_services.append(json_port)

                json_host['services'] = json_services
                self.json_object.append(json_host)

    def upload_file(self):
        #change this
        print(self.target_server)
        print(json.dumps(self.json_object))
        r = requests.post('{}/box'.format(self.target_server), json=self.json_object, verify=False)
        print(r.content)


def main():

    banner = """
 ===========================
     ___     _____ ____  
    | \ \   / /_ _/ ___| 
 _  | |\ \ / / | |\___ \ 
| |_| | \ V /  | | ___) |
 \___/   \_/  |___|____/ 

 ===========================\n
    """
    print(Color.BLUE + banner + Color.END)
    example = 'Examples:\n\n'
    example += "$ python3 client.py -i 192.168.50.3 -p 7777 -s 192.168.50.0/24 "
    parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter, epilog=example)
    sgroup = parser.add_argument_group("Main Arguments")
    sgroup.add_argument("-i", metavar="[IP]", dest='target_ip', default=False, type=str, help="IP of collaboration server", required=True)
    sgroup.add_argument("-p", metavar="[PORT]", dest='target_port', default=7777, type=int, help="Port of collab server", required=False)
    sgroup.add_argument("-s", metavar="[VICTIM IP/HOST/SUBNET]", dest="victim_addr", default=False, type=str, help="Host name, IP or subnet of victim", required=True)
    sgroup.add_argument("-n", action='store_false', dest="heavy", default=False, help="only run heavy scan")
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)

    args = parser.parse_args()
    
    target_server = "http://{}:{}".format(args.target_ip,args.target_port)

    initial_scan = "nmap -n -sn -PS80,23,443,21,22,25,3389,110,445,139,143,53,135,3306,8080,1723,111,995,993,5900,1025,587,8888 {} -oG - | awk '/Up$/{{print $2}}' > hosts_simple.txt".format(args.victim_addr)
    initial_scan_v = "nmap -sn {} -oG - | awk '/Up$/{{print $2}}' > hosts_detailed.txt".format(args.victim_addr)

    first_scan = "nmap -T5 -iL hosts_simple.txt --exclude-ports 502 -oX temp1.xml > firstscan.txt"
    second_scan = "nmap -T5 -iL hosts_detailed.txt -sSVC -p- --exclude-ports 502 -oX temp2.xml > secondscan.txt"

    
    p2 = log.progress("Connecting to JVIS server")
    try:
        request = requests.get(target_server, timeout=5, verify=False)
    except (requests.ConnectionError, requests.Timeout) as exception:
        p2.failure(Color.RED + "✘" + Color.END)
        print(Color.RED + "\nCould not connect to " + target_server + "\n")
        exit(1)
    p2.success(Color.GREEN + "✓" + Color.END)
    
    #fast host discovery
    if args.heavy is False:
        p1 = log.progress("Obtaining host list")
        #p1.status("test" + Color.END)
        try:
            os.remove('hosts_simple.txt')
        except:
            pass
        try:
            os.system(initial_scan)
        except:
            p1.failure(Color.RED + "✘" + Color.END)
            print(Color.RED + "\nScan on " + args.victim_addr + " failed\n")
            exit(1)

        filesize = os.path.getsize("hosts_simple.txt")
        if filesize == 0:
            p1.success(Color.YELLOW + "No hosts detected" + Color.END)
        else: 
            p1.success(Color.GREEN + "✓" + Color.END)



        try:
            os.remove('temp1.xml')
        except:
            pass

        try:
            os.remove('firstscan.txt')
        except:
            pass


        
        p3 = log.progress("Performing light-weight scan on " + args.victim_addr)
        try:
            os.system(first_scan)
        except:
            p3.failure(Color.RED + "✘" + Color.END)
            print(Color.RED + "\nScan on " + args.victim_addr + " failed\n")
            exit(1)

        try:
            l = open("firstscan.txt","r").read()
            print(l)
        except:
            p3.failure(Color.RED + "✘" + Color.END)
            print(Color.RED + "\nFailed to read scan\n")
            exit(1)

        p3.success(Color.GREEN + "✓" + Color.END)



        p4 = log.progress("Uploading results to jVis server")
        b = Beautifier('temp1.xml', target_server, args.victim_addr)
        #finish this
        try:
            b.parse_scan()
        except:
            p4.failure(Color.RED + "✘" + Color.END)
            print(Color.RED + "\nCould not parse file")
            exit(1)
        p4.success(Color.GREEN + "✓" + Color.END)

        p8 = log.progress("Uploading results to jVis server")
        try:
            b.upload_file()
        except:
            p8.failure(Color.RED + "✘" + Color.END)
            print(Color.RED + "\nCould not send results to " + target_server + "\n")
            exit(1)
        p8.success(Color.GREEN + "✓" + Color.END)

    #slower host discovery

    p5 = log.progress("Running heavy-weight scan")
    print("\n")
    try:
        os.remove('hosts_detailed.txt')
    except:
        pass

    os.system(initial_scan_v)

    try:
        os.remove('temp2.xml')
    except:
        pass
    
    try:
        os.remove('secondscan.txt')
    except:
        pass

    try:
        os.system(second_scan)
    except:
        p5.failure(Color.RED + "✘" + Color.END)
        print(Color.RED + "\nScan on " + args.victim_addr + " failed\n")
        exit(1)


    try:
        l = open("secondscan.txt","r").read()
        print(l)
    except:
        p5.failure(Color.RED + "✘" + Color.END)
        print(Color.RED + "\nFailed to read scan\n")
        exit(1)

    p5.success(Color.GREEN + "✓" + Color.END)


    p6 = log.progress("Parsing file")

    b = Beautifier('temp2.xml', target_server, args.victim_addr)
    #finish this
    try:
        b.parse_scan()
    except:
        p6.failure(Color.RED + "✘" + Color.END)
        print(Color.RED + "\nCould not parse file")
        exit(1)
    p6.success(Color.GREEN + "✓" + Color.END)

    p7 = log.progress("Uploading results to jVis server")
    try:
        b.upload_file()
    except:
        p7.failure(Color.RED + "✘" + Color.END)
        print(Color.RED + "\nCould not send results to " + target_server + "\n")
        exit(1)
    p7.success(Color.GREEN + "✓" + Color.END)

if __name__ == '__main__':
    main()
