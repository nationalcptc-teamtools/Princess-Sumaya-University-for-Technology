import argparse
import subprocess
import sys
import os
import json

import requests
from pwn import *
from bs4 import BeautifulSoup


# CPTC 12 = Theme Park -> ICS/OT is in scope. Scanning these ports on live
# control systems can crash them (Modbus/S7/DNP3 stacks handle nmap probes
# badly). A crashed ride = environment disruption = point loss / DQ risk.
OT_EXCLUDE_PORTS = (
    "102,"               # Siemens S7
    "502,"               # Modbus
    "789,"               # Red Lion
    "1911,4911,"         # Niagara Fox
    "1962,"              # PCWorx
    "2222,"              # EtherNet/IP
    "4840,"              # OPC-UA
    "5450,"              # OSIsoft PI
    "9600,"              # OMRON FINS
    "20000,20001,"       # DNP3
    "34962,34963,34964," # PROFINET
    "44818,"             # EtherNet/IP explicit messaging
    "47808"              # BACnet
)


class Color:
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    END = '\033[0m'


def run_scan(cmd, output_file=None, progress=None):
    # Old code used os.system() inside a bare try/except -- exit codes were
    # never inspected, so a failed nmap looked identical to a successful one
    # and downstream parsing worked on stale/empty files. On an 8h clock
    # that's a catastrophic silent loss.
    if progress:
        progress.status("running")
    try:
        result = subprocess.run(cmd, shell=True, check=False)
    except Exception as e:
        if progress:
            progress.failure(Color.RED + "✘ " + str(e) + Color.END)
        return False
    if result.returncode != 0:
        if progress:
            progress.failure(Color.RED + "✘ exit=%d" % result.returncode + Color.END)
        return False
    if output_file is not None and not os.path.exists(output_file):
        if progress:
            progress.failure(Color.RED + "✘ missing output: " + output_file + Color.END)
        return False
    return True


def _safe_remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


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
        hosts = soup.find_all('host')
        if not hosts:
            return
        for host in hosts:
            json_host = {}
            json_services = []
            # Only use IPv4 <address> -- MAC addresses are also <address>
            # elements and would otherwise clobber the IP field.
            addr_tag = host.find('address', attrs={'addrtype': 'ipv4'}) \
                       or host.find('address')
            json_host['ip'] = addr_tag.get('addr') if addr_tag else None
            status_tag = host.find('status')
            json_host['state'] = status_tag.get('state') if status_tag else None
            # Prefer a PTR (rDNS) name -- reverse DNS is more descriptive than
            # any user-supplied hostname; fall back to any <hostname>.
            hostname = None
            hnames = host.find_all('hostname')
            for h in hnames:
                if (h.get('type') or '').lower() == 'ptr':
                    hostname = h.get('name'); break
            if hostname is None and hnames:
                hostname = hnames[0].get('name')
            json_host['hostname'] = hostname
            json_host['subnet'] = self.subnet

            # OS fingerprint (nmap -O or smb-os-discovery). Pull the highest-
            # accuracy osmatch; if none, look for a Windows/Linux hint in any
            # script output (many services leak the OS in banners).
            os_hint = None
            osmatch = host.find('osmatch')
            if osmatch:
                os_hint = osmatch.get('name')
            if not os_hint:
                for script in host.find_all('script'):
                    out = (script.get('output') or '').lower()
                    if 'windows' in out:
                        os_hint = 'Windows'; break
                    if 'linux' in out:
                        os_hint = 'Linux'; break
            json_host['os'] = os_hint

            for p in host.find_all('port'):
                json_port = {}
                json_port['port'] = p.get('portid')
                json_port['protocol'] = p.get('protocol')
                state_tag = p.find('state')
                json_port['state'] = state_tag.get('state') if state_tag else None
                service_tag = p.find('service')
                json_port['name'] = service_tag.get('name') if service_tag else None
                json_port['version'] = service_tag.get('version') if service_tag else None
                # Old code did p.script.get('output') -- only returned the FIRST
                # script's output, silently losing e.g. smb-os-discovery when
                # ldap-rootdse also ran on the same port.
                scripts = p.find_all('script')
                if scripts:
                    json_port['script'] = "\n".join(
                        "[%s]\n%s" % (s.get('id', ''), s.get('output', ''))
                        for s in scripts
                    )
                else:
                    json_port['script'] = None
                json_services.append(json_port)

            json_host['services'] = json_services

            # Keep every host that answered any probe. Ones without an open
            # port in the scanned range still matter -- they might have an
            # open service on a port outside the current sweep, or need a
            # follow-up UDP/-p- scan. jVision now surfaces them so the whole
            # attack surface is visible, not just the currently-exploitable
            # slice.
            has_open = any((s.get('state') or '').lower() == 'open' for s in json_services)
            state = (json_host.get('state') or '').lower()
            if not has_open and state == 'up':
                # Server keys on json_host['state']; tag no-open-port survivors
                # so the UI can style them differently without a schema change.
                json_host['state'] = 'up (no open ports)'
            if state == 'up' or has_open:
                self.json_object.append(json_host)

    def upload_file(self):
        r = requests.post('{}/box'.format(self.target_server),
                          json=self.json_object, verify=False)
        return r.status_code == 200


def main():
    banner = """
 ===========================
     ___     _____ ____
    | \\ \\   / /_ _/ ___|
 _  | |\\ \\ / / | |\\___ \\
| |_| | \\ V /  | | ___) |
 \\___/   \\_/  |___|____/

 ===========================\n
    """
    print(Color.BLUE + banner + Color.END)
    example = 'Examples:\n\n'
    example += "$ python3 jvisionclient.py -i 192.168.50.3 -p 7777 -s 192.168.50.0/24"
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter, epilog=example)
    sgroup = parser.add_argument_group("Main Arguments")
    sgroup.add_argument("-i", metavar="[IP]", dest='target_ip', type=str,
                        help="IP of collaboration server", required=True)
    sgroup.add_argument("-p", metavar="[PORT]", dest='target_port', default=7777,
                        type=int, help="Port of collab server")
    sgroup.add_argument("-s", metavar="[VICTIM IP/HOST/SUBNET]", dest="victim_addr",
                        type=str, required=True,
                        help="Host name, IP or subnet of victim")
    # Bug fix: original was `store_false` with `default=False`, making -n a no-op
    # -- the light scan always ran regardless.
    sgroup.add_argument("-n", action='store_true', dest="heavy_only", default=False,
                        help="skip light scan; run only the heavy scan")
    sgroup.add_argument("-u", action='store_true', dest="udp", default=False,
                        help="also run UDP top-50 (SNMP/DNS/NetBIOS etc.)")
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(1)

    args = parser.parse_args()

    target_server = "http://{}:{}".format(args.target_ip, args.target_port)

    # Host discovery is layered so a firewalled ICMP-only host or a silent
    # Windows box with the firewall enabled still shows up:
    #   -PE  ICMP echo               (finds anything ping-friendly)
    #   -PP  ICMP timestamp          (some hosts reply only to this)
    #   -PM  ICMP netmask            (older gear)
    #   -PS  TCP SYN to popular ports (Windows/Linux services)
    #   -PA  TCP ACK to same ports   (bypasses stateless SYN filters)
    #   -PU  UDP probe to 53/161/137 (DNS/SNMP/NetBIOS often answer)
    #   -PR  ARP on the local link   (auto when appropriate, listed here for
    #        documentation; nmap ignores -PR for off-link targets)
    # Dedup + sort so the same host isn't scanned twice when it answers to
    # multiple probes.
    discovery_ports = (
        "21,22,23,25,53,80,88,110,111,135,139,143,389,443,445,"
        "465,514,587,631,636,873,993,995,1025,1433,1521,1723,"
        "2049,2222,3128,3306,3389,3690,5222,5432,5900,5985,5986,"
        "6379,8000,8008,8080,8081,8443,8888,9000,9090,9200,"
        "11211,27017"
    )
    ping_flags = (
        "-PE -PP -PM "
        "-PS{ports} -PA{ports} -PU53,161,137 -PR"
    ).format(ports=discovery_ports)

    initial_scan = (
        "nmap -n -sn {ping} {target} -oG - 2>&1 "
        "| awk '/Up$/{{print $2}}' | sort -uV > hosts_simple.txt"
    ).format(ping=ping_flags, target=args.victim_addr)

    initial_scan_v = (
        "nmap -n -sn {ping} {target} -oG - 2>&1 "
        "| awk '/Up$/{{print $2}}' | sort -uV > hosts_detailed.txt"
    ).format(ping=ping_flags, target=args.victim_addr)

    common_flags = "-n -T4 --min-rate 1000 --host-timeout 20m -Pn"

    first_scan = (
        "nmap {flags} -iL hosts_simple.txt "
        "--exclude-ports {excl} -oA temp1 > firstscan.txt 2>&1"
    ).format(flags=common_flags, excl=OT_EXCLUDE_PORTS)

    second_scan = (
        "nmap {flags} -sS -sV -sC -p- -iL hosts_detailed.txt "
        "--exclude-ports {excl} -oA temp2 > secondscan.txt 2>&1"
    ).format(flags=common_flags, excl=OT_EXCLUDE_PORTS)

    udp_scan = (
        "nmap {flags} -sU --top-ports 50 -iL hosts_detailed.txt "
        "--exclude-ports {excl} -oA temp2_udp > udpscan.txt 2>&1"
    ).format(flags=common_flags, excl=OT_EXCLUDE_PORTS)

    if os.geteuid() != 0:
        print(Color.YELLOW +
              "[!] not running as root -- -sS/-sU will silently fall back or fail\n" +
              Color.END)

    p2 = log.progress("Connecting to JVIS server")
    try:
        requests.get(target_server, timeout=5, verify=False)
    except (requests.ConnectionError, requests.Timeout):
        p2.failure(Color.RED + "✘" + Color.END)
        print(Color.RED + "\nCould not connect to " + target_server + "\n")
        exit(1)
    p2.success(Color.GREEN + "✓" + Color.END)

    if not args.heavy_only:
        p1 = log.progress("Obtaining host list (fast discovery)")
        _safe_remove('hosts_simple.txt')
        if not run_scan(initial_scan, output_file='hosts_simple.txt', progress=p1):
            print(Color.RED + "\nHost discovery failed on " + args.victim_addr + "\n")
            exit(1)
        if os.path.getsize('hosts_simple.txt') == 0:
            p1.success(Color.YELLOW + "no hosts detected" + Color.END)
        else:
            p1.success(Color.GREEN + "✓" + Color.END)

            _safe_remove('temp1.xml')
            _safe_remove('firstscan.txt')

            p3 = log.progress("Performing light-weight scan on " + args.victim_addr)
            if not run_scan(first_scan, output_file='temp1.xml', progress=p3):
                exit(1)
            try:
                print(open('firstscan.txt').read())
            except IOError:
                p3.failure(Color.RED + "✘ could not read scan output" + Color.END)
                exit(1)
            p3.success(Color.GREEN + "✓" + Color.END)

            p4 = log.progress("Parsing light-weight scan")
            b = Beautifier('temp1.xml', target_server, args.victim_addr)
            try:
                b.parse_scan()
            except Exception as e:
                p4.failure(Color.RED + "✘ " + str(e) + Color.END)
                exit(1)
            p4.success(Color.GREEN + "✓" + Color.END)

            p8 = log.progress("Uploading light-weight results to jVis server")
            try:
                b.upload_file()
            except Exception as e:
                p8.failure(Color.RED + "✘ " + str(e) + Color.END)
                exit(1)
            p8.success(Color.GREEN + "✓" + Color.END)

    p5 = log.progress("Running heavy-weight scan (host discovery)")
    _safe_remove('hosts_detailed.txt')
    if not run_scan(initial_scan_v, output_file='hosts_detailed.txt', progress=p5):
        exit(1)
    if os.path.getsize('hosts_detailed.txt') == 0:
        p5.success(Color.YELLOW + "no hosts detected -- skipping heavy scan" + Color.END)
        return
    p5.success(Color.GREEN + "✓" + Color.END)

    _safe_remove('temp2.xml')
    _safe_remove('secondscan.txt')

    p5b = log.progress("Running heavy-weight scan (TCP full)")
    if not run_scan(second_scan, output_file='temp2.xml', progress=p5b):
        exit(1)
    try:
        print(open('secondscan.txt').read())
    except IOError:
        p5b.failure(Color.RED + "✘ could not read scan output" + Color.END)
        exit(1)
    p5b.success(Color.GREEN + "✓" + Color.END)

    p6 = log.progress("Parsing heavy-weight scan")
    b = Beautifier('temp2.xml', target_server, args.victim_addr)
    try:
        b.parse_scan()
    except Exception as e:
        p6.failure(Color.RED + "✘ " + str(e) + Color.END)
        exit(1)
    p6.success(Color.GREEN + "✓" + Color.END)

    p7 = log.progress("Uploading heavy-weight results to jVis server")
    try:
        b.upload_file()
    except Exception as e:
        p7.failure(Color.RED + "✘ " + str(e) + Color.END)
        exit(1)
    p7.success(Color.GREEN + "✓" + Color.END)

    if args.udp:
        p9 = log.progress("Running UDP top-50 scan")
        _safe_remove('temp2_udp.xml')
        _safe_remove('udpscan.txt')
        if not run_scan(udp_scan, output_file='temp2_udp.xml', progress=p9):
            print(Color.YELLOW + "\nUDP scan failed -- continuing without it\n" + Color.END)
        else:
            p9.success(Color.GREEN + "✓" + Color.END)
            p10 = log.progress("Parsing + uploading UDP results")
            b = Beautifier('temp2_udp.xml', target_server, args.victim_addr)
            try:
                b.parse_scan()
                b.upload_file()
                p10.success(Color.GREEN + "✓" + Color.END)
            except Exception as e:
                p10.failure(Color.RED + "✘ " + str(e) + Color.END)


if __name__ == '__main__':
    main()
