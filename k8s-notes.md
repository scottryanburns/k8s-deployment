## K8s Notes
k8s deployment on ubuntu 24
VIP =  192.168.200.50 #using haproxy & keepalived

Control Planes:
nobu-ctrl01 = 192,168.200.51
nobu-ctrl02 = 192,168.200.52
nobu-ctrl03 = 192,168.200.53

Workers:
nobu-wrk01 = 192.168.200.54
nobu-wrk02 = 192.168.200.55
nobu-wrk03 = 192.168.200.56

## Proxmox Commands
### Purging machines
qm destroy 401 --purge
qm destroy 402 --purge
qm destroy 403 --purge
qm destroy 404 --purge
qm destroy 405 --purge
qm destroy 406 --purge

### Cloning machines
qm clone 9002 401 --name nobu-ctrl01 --full 1
qm clone 9002 402 --name nobu-ctrl02 --full 1
qm clone 9002 403 --name nobu-ctrl03 --full 1
qm clone 9002 404 --name nobu-wrk01 --full 1
qm clone 9002 405 --name nobu-wrk02 --full 1
qm clone 9002 406 --name nobu-wrk03 --full 1
