#!/usr/bin/python -u

import os
import socket
import struct
import sys
import select
import fcntl
import time

def debug(message):
  sys.stderr.write(time.asctime()+": "+message) 

def xor(xorstr,xorsec,i,xorseclen):
  # input:
  # xorstr - data
  # xorsec - list xoring secret
  # i - where are we in the xoring secret
  # xorseclen - the length of xoring secret
  # return:
  # i - where did we finish in the xoring secret
  # s - xorred data

  xorstr = map (ord, xorstr)
  xorstrrange = range(len(xorstr))

  for c in xorstrrange:
    xorstr[c] = (xorstr[c]^xorsec[i])
    i += 1
    if i >= xorseclen:
      i = 0

  s = ""
  return i,s.join(map(chr, xorstr))


# main data exchange function
def exchange(s1,s2):
  # input:
  # s1 - socket 1 object
  # s2 - socket 2 object
  # return:
  # nothing :)

  # setting every description to be non blocking 
  fcntl.fcntl(s1, fcntl.F_SETFL, os.O_NONBLOCK|os.O_NDELAY) 
  fcntl.fcntl(s2, fcntl.F_SETFL, os.O_NONBLOCK|os.O_NDELAY)

  secret = map(ord,"testowysecret")
  secretlen = len(secret) 
  secreti = 0
  secreto = 0

  while 1:
    toread,towrite,[]=select.select([s1,s2],[s1,s2],[],30)
    
    if s1 in toread and s2 in towrite:
      data = s1.recv(1500)
      secreti,data = xor(data,secret,secreti,secretlen)
      if len(data) == 0:
        break
      else:
        s2.send(data)

    if s2 in toread and s1 in towrite: 
      data = s2.recv(1500)
      secreto,data = xor(data,secret,secreto,secretlen)
      if len(data) == 0:
        break
      else:
        s1.send(data)

# preparing a socks4 or socks4a connection
def socks4(s,host,port):
  # input:
  # s - socket object
  # host - destination host either IP or a name
  # port - destination port
  # return:
  # 1 - if ready
  # 0 - if needs authentication 

  try:
    data = struct.pack('!2BH',4,1,port)+socket.inet_aton(host)+chr(0)
  except socket.error:
    data = struct.pack('!2BH',4,1,port)+socket.inet_aton('0.0.0.1')+chr(0)+host+chr(0)

  s.send(data)
  data = s.recv(256)
  code = struct.unpack('BBH',data[:4])[1]

  if code == 90:
    return 1 
  else:
    return 0 

# preaparing a socks5 connection
def socks5(s,host,port):
  # input:
  # s - socket object
  # host - destination host either IP or a name
  # port - destination port
  # return:
  # 1 - if ready
  # 0 - if needs authentication 

  data = struct.pack('!3B',5,1,0)
  s.send(data)
  data = s.recv(1024)
  try:
    auth = struct.unpack('2B',data)[1]
  except:
    return 0
  if auth != 255:
    nport = struct.pack('!H',port)
    try:
      data = struct.pack('!4B',5,1,0,1)+socket.inet_aton(host)+nport
    except socket.error:
      data = struct.pack('!5B',5,1,0,3,len(host))+host+nport

    s.send(data)
    data = s.recv(256)
    try:
      code = struct.unpack('BBH',data[:4])[1]
    except:
      return 0

    if code == 0:
      return 1 
    else:
      return 0

  else:
    return 0 

#### main stuff
if __name__ == '__main__':

  if len(sys.argv) >= 5: 
    phost = sys.argv[1]
    pport = int(sys.argv[2])
    host  = sys.argv[3]
    port  = int(sys.argv[4])
    if len(sys.argv) == 6:
      ver = int(sys.argv[5])
    else:
      ver = 5

    socks_try = 0
    socks_limit = 1 

    while 1:
      socks = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

      connected = 1
      if socks_try < socks_limit:
        try:
          socks.connect((phost, pport))
#          debug("[+] connecting via "+str(phost)+":"+str(pport)+"\n")
        except socket.error:
#          debug("[-] problem connecting to "+str(phost)+":"+str(pport)+"\n")
          connected = 0

      else:
        try:
          socks.connect((host, port))
#          debug("[+] connecting direct to "+str(host)+":"+str(port)+"\n")
        except:
#          debug("[-] problem connecting direct to "+str(host)+":"+str(port)+"\n")
          connected = 0

      if connected == 1:

        if (socks_try >= socks_limit) or (ver == 5 and socks5(socks,host,port) == 1) or (ver == 4 and socks4(socks,host,port) == 1): 

          ssh = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
          debug("[+] connected to "+str(host)+":"+str(port)+"\n")

          try:
            ssh.connect(('127.0.0.1',22))
            exchange(ssh,socks)
            socks.shutdown(2)
            ssh.shutdown(2)
            ssh.close()
            debug("[+] connection closed\n")
          except:
            pass
        
#        else:
#          debug("[-] socks server couldn't establish the connection to "+str(host)+":"+str(port)+"\n") 
        
        socks.close()
      
      else:
        socks.close()
        if socks_try >= socks_limit:
          socks_try = 0
        socks_try += 1
         
      time.sleep(30)

  else:
    sys.stderr.write("usage: "+sys.argv[0]+" ip_socks port_socks ip_dest port_dest [socks_ver]\n")

