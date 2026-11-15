# Process

### 1  Need to configure it on the bios

### 2. Verify that machine supports it

```bash
# check interface
ip a
# run
sudo ethtool <interface> | grep Wake

# You should see
Supports Wake-on: pumbg # if you have a "d" here it doesn't support it. if you find "g" it does.
Wake-on: g # if it says "g" everything is ok. if it doesn't say "g" we can change it


# Got stuck on this part
# change Wake-on to g
vim /etc/network/interfaces
# add this line below iface <interface> inet static
post-up /usr/sbin/ethtool -s <interface> wol g

```
