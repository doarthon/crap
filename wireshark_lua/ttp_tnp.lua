--
-- Trivial Networking Protocol and also TTP dissector for wireshark
--
-- $Id: 20120722$
-- $Date: 2012-07-22 13:48:39$
-- $Author: Marek Lukaszuk$
--
-- usage:
--    wireshark -X lua_script:ttp_tnp.lua
--
-- or you can copy the file to:
--   C:\Documents and Settings\your_user\Application Data\Wireshark\plugins\
--   or
--   /home/your_user/.wireshark/plugins/
--
-- any ideas, suggestions for changes, new versions of the protocol
-- please contact Marek Lukaszuk
--
-- doc about LUA support in wireshark:
-- https://www.wireshark.org/docs/wsug_html_chunked/wsluarm.html
--
-- script version: 20120504
--
-- TODO:
-- - check TODO in the code ;)
-- - see if it is possible to reassemble TNP packets,
--   ^^ (it should be possible using global array,
--   ^^ frag pkts will have the same src,dst and seq
-- - optimize,
-- - add preferences for some features,
-- - figure out how TTP knows what protocol is inside under what offset
--
-- ChangeLog:
-- 20120517 - more logic to decode TTP,
-- 20120504 - some small fixes,
--          - added ugly hack to decode/guess more protocols,
-- 20120503 - added more protocols that can be decoded in TTP,
--          - TTP can be decoded from inside IP (ip.proto==84),
--          - added TTP hint decode,
-- 20120208 - added support for decoding ethertype 0x88b5

tnp_proto  = Proto("TNP","Trivial Networking Protocol")

-----------------------------------------
-- this is outside to speed up dissection

local tnp_proto_protocol_types = {
  [1] = "hello",
  [2] = "control",
  [3] = "rdp",
  [4] = "udp",
  [5] = "tunnel",
  [6] = "stp",
  [7] = "sdrp",
}

local tnp_proto_rdp_known_ports = {
  [19] = "chargen",
  [23] = "vty",
  [24] = "vty_idp",
  [38] = "mgd",
  [971] = "utmd_sigdb",
  [972] = "relay_server",
  [973] = "picinfo",
  [974] = "dcp_prov",
  [975] = "iked1_spu_spu",
  [976] = "iked2_spu_spu",
  [977] = "iked3_spu_spu",
  [978] = "iked4_spu_spu",
  [979] = "appid",
  [980] = "appidd",
  [981] = "kmd1_spu",
  [982] = "kmd2_spu",
  [983] = "kmd3_spu",
  [984] = "kmd4_spu",
  [985] = "bulkstats",
  [986] = "idp",
  [987] = "iked_cfg",
  [988] = "cprod_idp",
  [989] = "uac",
  [990] = "pfe_pic",
  [991] = "ha_cs_status",
  [992] = "rsdd",
  [993] = "iked_spu",
  [994] = "maclearn",
  [995] = "iked_re",
  [996] = "fwauth",
  [997] = "sampled",
  [998] = "aaa_authd",
  [1000] = "utm_as",
  [1001] = "utm_av",
  [1002] = "utm_cf",
  [1003] = "utm_mn",
  [1004] = "utm_uf",
  [1005] = "utm_srv",
  [1008] = "usp_trace",
  [1009] = "usp",
  [1010] = "router_cm",
  [1011] = "ppm",
  [1012] = "snmp_master",
  [1013] = "l2ald",
  [1014] = "mde_agent",
  [1015] = "nsd",
  [1016] = "msgrelay",
  [1017] = "agentx_master",
  [1020] = "pfe",
  [1021] = "chassis",
  [1022] = "cprod",
  [1023] = "ipc_test",
}

local tnp_proto_udp_known_ports = {
  [67] = "bootp",
  [69] = "tftp",
  [123] = "ntp",
  [124] = "mcontrol",
  [514] = "syslog",
  [999] = "idpd",
  [1006] = "rtlog",
  [1007] = "eedebug_pkt_trace",
  [1018] = "pkt_cap",
  [1019] = "traffic",
}

local tnp_proto_control_types = {
  [1] = "echo request",
  [2] = "echo replay",
}

local tnp_proto_tunnel_types = {
  [0] = "unknown",
  [1] = "rx_l2",
  [2] = "tx_l2",
  [3] = "rx_l3",
  [4] = "tx_l3",
  [5] = "rx_discard",
  [6] = "rx_l2_sample",
  [7] = "rx_l3_sample",
}

local tnp_proto_tunnel_priority = {
  [0] = "none",
  [1] = "discard",
  [2] = "low",
  [3] = "medium",
  [4] = "high",
}

-- local tnp_proto_tunnel_nhdstmask = {
-- }

local tnp_proto_protocols = {
  [0] = "UNKNOWN",
  [1] = "NULL",
  [2] = "IPV4",
  [3] = "TAG_IPV4",
  [4] = "IPV4_TAG",
  [5] = "TAG",
  [6] = "IPV6",
  [7] = "TAG_IPV6",
  [8] = "IPV6_TAG",
  [9] = "ARP",
  [10] = "CLNP",
  [11] = "TNP",
  [12] = "CYCLO_CYCLE",
  [13] = "CYCLO_SEND",
  [14] = "CCC",
  [15] = "TAG_CCC",
  [16] = "CCC_TAG",
  [17] = "DECAPS",
  [18] = "TAG_ANY",
  [19] = "ANY_TAG",
  [20] = "MLPPP",
  [21] = "MLFR",
  [22] = "DECRYPT",
  [23] = "TCC",
  [24] = "TAG_TCC",
  [25] = "TCC_TAG",
  [26] = "MFR",
  [27] = "VPLS",
  [28] = "TAG_VPLS",
  [29] = "VPLS_TAG",
  [30] = "VPLS_SRC",
  [31] = "VPLS_FLOOD",
  [32] = "CLNP_TAG",
  [33] = "TAG_CLNP",
  [34] = "MULTILOOKUP",
  [35] = "L2_BRIDGE",
  [36] = "ANY",
  [37] = "REDIRECT_V4",
  [38] = "REDIRECT_V6",
  [39] = "MULTISERVICE",
  [40] = "VMEMBERS",
  [41] = "MSTI",
  [42] = "DMXT_IPV4",
  [43] = "DMXT_IPV6",
  [44] = "DHCPSNOOP",
  [45] = "DEVRT",
  [46] = "FABRIC_MULTICAST",
  [47] = "FABRIC_REPLICATION",
  [48] = "R2CP",
  [49] = "FIBRECHANNEL",
  [50] = "FMEMBERS",
  [51] = "DCFABRIC",
  [52] = "PPPOE",
  [53] = "JNPR_FAB",
  [54] = "STEERING",
  [55] = "GTPU",
  [56] = "MAX",
}

local tnp_proto_fragments = {
  [0] = "none",
  [127] = "mask",
  [128] = "first/more",
}

local f  = tnp_proto.fields
f.ver    = ProtoField.uint8("tnp.ver","version",base.HEX,nil,0xF0)
f.proto  = ProtoField.uint8("tnp.proto","protocol",base.HEX,tnp_proto_protocol_types,0x0F)
f.frag   = ProtoField.uint8("tnp.frag","fragment",nil,tnp_proto_fragments)
f.len    = ProtoField.uint16("tnp.len","length",base.DEC)
f.seq    = ProtoField.uint16("tnp.seq","sequence",base.DEC)
f.pad    = ProtoField.uint8("tnp.pad","padding",base.HEX)
f.ttl    = ProtoField.uint8("tnp.ttl","ttl",base.DEC)
f.saddr  = ProtoField.bytes("tnp.addr.src","src addr",base.HEX)
f.daddr  = ProtoField.bytes("tnp.addr.dst","dst addr",base.HEX)
-- tnp hello
f.h_int  = ProtoField.uint16("tnp.hello.int","interval (ms)",base.DEC)
f.h_exp  = ProtoField.uint16("tnp.hello.exp","expire (ms)",base.DEC)
f.hn1_ad = ProtoField.bytes("tnp.hello.neigh1.addr","neighbour address",base.HEX)
f.hn1_mt = ProtoField.uint16("tnp.hello.neigh1.mtu","mtu",base.DEC)
f.hn1_hc = ProtoField.uint16("tnp.hello.neigh1.hc","hop count",base.DEC)
f.hn2_ad = ProtoField.bytes("tnp.hello.neigh2.addr","neighbour address",base.HEX)
f.hn2_mt = ProtoField.uint16("tnp.hello.neigh2.mtu","mtu",base.DEC)
f.hn2_hc = ProtoField.uint16("tnp.hello.neigh2.hc","hop count",base.DEC)
-- tnp udp
f.usport = ProtoField.uint16("tnp.udp.port.src","src port",base.DEC,tnp_proto_udp_known_ports)
f.udport = ProtoField.uint16("tnp.udp.port.dst","dst port",base.DEC,tnp_proto_udp_known_ports)
f.ulen   = ProtoField.uint16("tnp.udp.length","length",base.DEC)
f.uchks  = ProtoField.uint16("tnp.udp.checksum","cheksum",base.HEX)
f.udata  = ProtoField.bytes("tnp.udp.data","data")
-- tnp rdp
f.rfsyn  = ProtoField.uint8("tnp.rdp.flags.syn","syn",nil,nil,0x80)
f.rfack  = ProtoField.uint8("tnp.rdp.flags.ack","ack",nil,nil,0x40)
f.rfeack = ProtoField.uint8("tnp.rdp.flags.eack","eack",nil,nil,0x20)
f.rfrst  = ProtoField.uint8("tnp.rdp.flags.rst","rst",nil,nil,0x10)
f.rfnul  = ProtoField.uint8("tnp.rdp.flags.nul","nul",nil,nil,0x08)
f.rfkeep = ProtoField.uint8("tnp.rdp.flags.keepalive","keepalive",nil,nil,0x04)
f.rfver  = ProtoField.uint8("tnp.rdp.ver","version",base.DEC,nil,0x03)
f.rhl    = ProtoField.uint8("tnp.rdp.hl","header length",base.DEC)
f.rsport = ProtoField.uint16("tnp.rdp.port.src","src port",base.DEC,tnp_proto_rdp_known_ports)
f.rdport = ProtoField.uint16("tnp.rdp.port.dst","dst port",base.DEC,tnp_proto_rdp_known_ports)
f.rlen   = ProtoField.uint16("tnp.rdp.length","length",base.DEC)
f.rseq   = ProtoField.uint64("tnp.rdp.seq","seq num",base.DEC)
f.rack   = ProtoField.uint64("tnp.rdp.ack","ack num",base.DEC)
f.rchks  = ProtoField.uint16("tnp.rdp.checksum","checksum",base.HEX)
f.rpad   = ProtoField.uint16("tnp.rdp.pad","padding",base.HEX)
f.rsywin = ProtoField.uint16("tnp.rdp.window","window",base.DEC)
f.rsymtu = ProtoField.uint16("tnp.rdp.mtu","mtu",base.DEC)
f.rsyopt = ProtoField.uint16("tnp.rdp.options","options",base.HEX)
f.rsosdm = ProtoField.uint8("tnp.rdp.options.sdm","sdm",nil,nil,0x0001)
f.rsokpa = ProtoField.uint8("tnp.rdp.options.keepalive","keepalive",nil,nil,0x0002)
f.rdata  = ProtoField.bytes("tnp.rdp.data","data")
-- tnp control
f.elen   = ProtoField.uint64("tnp.control.length","length",base.DEC)
f.etype  = ProtoField.uint16("tnp.control.type","type",base.DEC,tnp_proto_control_types)
f.eid    = ProtoField.uint16("tnp.control.id","id",base.DEC)
f.edata  = ProtoField.bytes("tnp.control.data","data")

function tnp_proto.dissector(buf,pinfo,tree)

    pinfo.cols.protocol = "TNP"

    local subtree = tree:add(tnp_proto,buf(),"Trivial Networking Protocol")

    --==--==--==--==--
    -- main TNP header
    local tnpheader = subtree:add("TNP header")

    local flags = buf(0,1):uint()
    local tnpver = tonumber(bit.rshift(flags,4))
    local tnpproto = tonumber(bit.band(flags,0x0F))

    if (tnpver == 3) then pinfo.cols.protocol:append("v3")
    elseif (tnpver == 2) then pinfo.cols.protocol:append("v2")
    elseif (tnpver == 1) then pinfo.cols.protocol:append("v1")
    else
      pinfo.cols.protocol:append("v?")
      -- unknown version, probably malformed packet
      -- dropping out
      return
     end

    tnpheader:add(f.ver,buf(0,1))

    local tnpprotoname = "unknown"

    if tnp_proto_protocol_types[tnpproto] ~= nil then
      tnpprotoname = tnp_proto_protocol_types[tnpproto]
    end

    tnpheader:add(f.proto,buf(0,1))

    local tnpfrag = "number"
    local tnpfragval = buf(1,1):uint()
    if (tnpfragval == 0) then
      tnpfrag = "none"
    elseif (tnpfragval == 128) then
      tnpfrag = "first/more"
      pinfo.cols.info:append(", more frags")
    elseif (tnpfragval == 127)  then
      tnpfrag = "mask"
    end

    local tnpdatalen = buf(2,2):uint()
    tnpheader:add(f.frag,buf(1,1))
    tnpheader:add(f.len,buf(2,2))
    tnpheader:add(f.seq,buf(4,2))

    local tnpsrcaddr=""
    local tnpdstaddr=""

    pinfo.cols.info = ""
    local offset = 16 -- end of the header for TNPv2 and TNPv3
    if (tnpver == 1) then
      tnpheader:add(f.daddr,buf(6,1))
      tnpheader:add(f.saddr,buf(7,1))
      pinfo.cols.info:append(buf(7,1) .. " > " .. buf(6,1))
      offset = 8 -- end of the header for TNPv1
    else
      -- this is for TNPv2 and TNPv3
      tnpheader:add(f.pad,buf(6,1))
      tnpheader:add(f.ttl,buf(7,1))
      tnpheader:add(f.daddr,buf(8,4))
      tnpheader:add(f.saddr,buf(12,4))
      pinfo.cols.info:append(buf(12,4) .. " > " .. buf(8,4))
    end

    pinfo.cols.info:append(" proto:" .. tnpprotoname)

    -- TODO: why this doesn't work?
    -- pinfo.cols.src:set(tnpsrcaddr)
    -- pinfo.cols.dst:set(tnpdstaddr)

    -- if this is a fragment we don't go any further
    if (tnpfrag == "number") then
      pinfo.cols.info:append(", fragment")
      -- just normal data
      local inside_dis = Dissector.get ("data")
      inside_dis:call (buf(offset):tvb(), pinfo, tree)
      return
    end

    --==--==--==--==--==--==--==
    -- protocol types start here
    --
    if (tnpprotoname == "hello") then
      --------------
      --- hello type

      local tnphello = subtree:add("TNP Hello msg")

      local tnphellointval = buf(offset,2):uint()
      local tnphelloexpireval = buf(offset+2,2):uint()

      tnphello:add(f.h_int,buf(offset,2))
      tnphello:add(f.h_exp,buf(offset+2,2))
      pinfo.cols.info:append(", interval: " .. tnphellointval .. ", expire: " .. tnphelloexpireval)

      local neigh1
      if (tnpver == 1) then
        neigh1 = tnphello:add(f.hn1_ad,buf(offset+6,1))
        neigh1:add(f.hn1_mt,buf(offset+4,2))
        neigh1:add(f.hn1_hc,buf(offset+7,1))
      else
        neigh1 = tnphello:add(f.hn1_ad,buf(offset+6,4))
        neigh1:add(f.hn1_mt,buf(offset+4,2))
        neigh1:add(f.hn1_hc,buf(offset+10,2))
      end

      -- second neighbour, only for TNPv2 and above
      if (tnpdatalen>12 and tnpver > 1) then
        offset = offset + 12
        local neigh2 = tnphello:add(f.hn2_ad,buf(offset+2,4))
        --pinfo.cols.info:append(", n2: " .. n)
        neigh2:add(f.hn2_mt,buf(offset,2))
        neigh2:add(f.hn2_hc,buf(offset+6,2))
      end

    elseif (tnpprotoname == "udp") then
      ------------
      --- udp type -- standard UDP - mostly

      local tnpudp = subtree:add("TNP UDP msg")
      tnpudp:add(f.usport,buf(offset,2))
      tnpudp:add(f.udport,buf(offset+2,2))
      tnpudp:add(f.ulen,buf(offset+4,2))
      tnpudp:add(f.uchks,buf(offset+6,2))
      -- tnpudp:add(f.udata,buf(offset+8))

      local srcport = buf(offset,2):uint()
      local dstport = buf(offset+2,2):uint()
      local tsrcport = srcport
      local tdstport = dstport
      if tnp_proto_udp_known_ports[srcport] ~= nil then
        tsrcport = srcport .. " (" ..tnp_proto_udp_known_ports[srcport] ..")"
      end
      if tnp_proto_udp_known_ports[dstport] ~= nil then
        tdstport = dstport .. " (" ..tnp_proto_udp_known_ports[dstport] ..")"
      end

      pinfo.cols.info:append(", " .. tsrcport .. " > " .. tdstport )

      -- our own SNTP dissector
      if srcport == 123 or dstport == 123 then
        sntp_proto.dissector:call (buf(offset+8):tvb(), pinfo, tree)
      else
        -- just normal data
        local inside_dis = Dissector.get ("data")
        inside_dis:call (buf(offset+8):tvb(), pinfo, tree)
      end

    elseif (tnpprotoname == "rdp") then
      -----------------------------------
      --- rdp type - RFC 908 and RFC 1151

      local rdp = subtree:add("TNP rdp msg (RFC 908 & 1151)")

      local rdpflag = buf(offset,1):uint()

      rdpflags = rdp:add(buf(offset,1),"flags    : 0x" .. buf(offset,1))
      rdpflags:add(f.rfsyn,buf(offset,1))
      rdpflags:add(f.rfack,buf(offset,1))
      rdpflags:add(f.rfeack,buf(offset,1))
      rdpflags:add(f.rfrst,buf(offset,1))
      rdpflags:add(f.rfnul,buf(offset,1))
      rdpflags:add(f.rfkeep,buf(offset,1))
      rdpflags:add(f.rfver,buf(offset,1))

      local rdpver = 2
      local rdpsyn = 0

      -- TODO can we optimize this?
      -- maybe make a global array
      -- with all possible values as indexes

      if (tonumber(bit.band(rdpflag,0x02)) > 0 ) then
        pinfo.cols.info:append(", ver:2")
      end
      if (tonumber(bit.band(rdpflag,0x01)) > 0 ) then
        pinfo.cols.info:append(", ver:1");
        rdpver=1
      end

      pinfo.cols.info:append(", [")
      if (tonumber(bit.band(rdpflag,0x80)) > 0 ) then
        pinfo.cols.info:append("syn,")
        rdpsyn = 1
      end
      if (tonumber(bit.band(rdpflag,0x40)) > 0 ) then pinfo.cols.info:append("ack,") end
      if (tonumber(bit.band(rdpflag,0x20)) > 0 ) then pinfo.cols.info:append("eak,") end
      if (tonumber(bit.band(rdpflag,0x10)) > 0 ) then pinfo.cols.info:append("rst,") end
      if (tonumber(bit.band(rdpflag,0x08)) > 0 ) then pinfo.cols.info:append("nul,") end
      if (tonumber(bit.band(rdpflag,0x04)) > 0 ) then pinfo.cols.info:append("keepalive,") end

      pinfo.cols.info:append("]")

      rdp:add(f.rhl,buf(offset+1,1))

      local srcport
      local dstport
      if (rdpver == 1) then
        srcport = buf(offset+2,1):uint()
        dstport = buf(offset+3,1):uint()
        rdp:add(f.rsport,buf(offset+2,1))
        rdp:add(f.rdport,buf(offset+3,1))

        offset = offset+4
      else
        srcport = buf(offset+2,2):uint()
        dstport = buf(offset+4,2):uint()
        rdp:add(f.rsport,buf(offset+2,2))
        rdp:add(f.rdport,buf(offset+4,2))
        offset = offset+6
      end

      if tnp_proto_rdp_known_ports[srcport] ~= nil then
        srcport = srcport .. " (" ..tnp_proto_rdp_known_ports[srcport] ..")"
      end
      if tnp_proto_rdp_known_ports[dstport] ~= nil then
        dstport = dstport .. " (" ..tnp_proto_rdp_known_ports[dstport] ..")"
      end

      pinfo.cols.info:append(", " .. srcport .. " > " .. dstport)

      local tnprdpdl = buf(offset,2):uint()

      rdp:add(f.rlen,buf(offset,2))
      rdp:add(f.rseq,buf(offset+2,4))
      rdp:add(f.rack,buf(offset+6,4))
      rdp:add(f.rchks,buf(offset+10,2))

      if (rdpsyn == 1) then
        rdp:add(f.rsywin,buf(offset+12,2))
        rdp:add(f.rsymtu,buf(offset+14,2))
        rdp:add(f.rsyopt,buf(offset+16,2))
        rdp:add(f.rsosdm,buf(offset+16,2))
        rdp:add(f.rsokpa,buf(offset+16,2))
        rdp:add(f.rdata,buf(offset+18))
      else
        rdp:add(f.rpad,buf(offset+12,2))
        -- rdp:add(f.rdata,buf(offset+14))
        -- just normal data
        local inside_dis = Dissector.get ("data")
        inside_dis:call (buf(offset+14):tvb(), pinfo, tree)
      end

    elseif (tnpprotoname == "control") then
      ---------------
      -- control type

      local control = subtree:add("TNP control msg")
      control:add(f.elen,buf(offset,4))
      control:add(f.etype,buf(offset+4,2))
      control:add(f.eid,buf(offset+6,2))
      control:add(f.edata,buf(offset+8))

      local ctrltypev = buf(offset+4,2):uint()

      local ctrltype = "unknown"
      if tnp_proto_control_types[buf(offset+4,2):uint()] ~= nil then
        ctrltype = tnp_proto_control_types[buf(offset+4,2):uint()]
      end

      pinfo.cols.info:append(", type:" .. ctrltype .. ", id:" .. buf(offset+6,2):uint())

    elseif (tnpprotoname == "tunnel") then
      --------------
      -- tunnel type
      jttp_proto.dissector:call(buf(offset):tvb(), pinfo, tree, tnpver)

    elseif (tnpprotoname == "stp") then
      -----------
      -- stp type
      -- TODO check if this is normal STP or something else ;)
      stp_dissector = Dissector.get ("stp")
      stp_dissector:call (buf(offset,tnpdatalen):tvb(), pinfo, tree)

    elseif (tnpprotoname == "sdrp") then
      ------------
      -- sdrp type
      local sdrp = subtree:add("TNP sdrp msg")
      -- TODO
    end
end


-- ---------------------------- --
-- Simple Network Time Protocol --
-- ---------------------------- --
-- https://tools.ietf.org/html/rfc4330
sntp_proto = Proto("SNTP","Simple Network Time Protocol")

local sntp_proto_li = {
  [0] = "no warning",
  [1] = "last minute has 61 seconds",
  [2] = "last minute has 59 seconds",
  [3] = "alarm condition (clock not synchronized)",
}

local sntp_proto_mode = {
  [0] = "reserved",
  [1] = "symmetric active",
  [2] = "symmetric passive",
  [3] = "client",
  [4] = "server",
  [5] = "broadcast",
  [6] = "reserved for NTP control message",
  [7] = "reserved for private use",
}

local sf = sntp_proto.fields
sf.li = ProtoField.uint8("sntp.li","leap indicator",base.DEC,sntp_proto_li,0xC0)
sf.vn = ProtoField.uint8("sntp.vn","Version",base.DEC,nil,0x38)
sf.mode = ProtoField.uint8("sntp.mode","mode",base.DEC,sntp_proto_mode,0x07)
sf.stratum = ProtoField.uint8("sntp.stratum","stratum",base.DEC)
sf.poll = ProtoField.uint8("sntp.poll","poll",base.HEX)
sf.precis = ProtoField.int8("sntp.precision","precision",base.DEC)
sf.rootdelay = ProtoField.uint32("sntp.root_delay","root delay",base.DEC)
sf.rootdispe = ProtoField.uint32("sntp.root_dispersion","root dispersion",base.DEC)
sf.refid = ProtoField.uint32("sntp.ref_id","reference id",base.HEX)
sf.refts = ProtoField.uint64("sntp.ref_ts","reference timestamp",base.HEX)
sf.orgts = ProtoField.uint64("sntp.org_ts","originate timestamp",base.HEX)
sf.rxts = ProtoField.uint64("sntp.tx_ts","receive timestamp",base.HEX)
sf.txts = ProtoField.uint64("sntp.rx_ts","transmit timestamp",base.HEX)

function sntp_proto.dissector(buf,pinfo,tree)
  local subtree = tree:add(sntp_proto,buf(),"Simple Network Time Protocol")
  subtree:add(sf.li,buf(0,1))
  subtree:add(sf.vn,buf(0,1))
  subtree:add(sf.mode,buf(0,1))
  subtree:add(sf.stratum,buf(1,1))
  subtree:add(sf.poll,buf(2,1))
  subtree:add(sf.precis,buf(3,1))
  subtree:add(sf.rootdelay,buf(4,4))
  subtree:add(sf.rootdispe,buf(8,4))
  subtree:add(sf.refid,buf(12,4))
  subtree:add(sf.refts,buf(16,8))
  subtree:add(sf.orgts,buf(24,8))
  subtree:add(sf.rxts,buf(32,8))
  subtree:add(sf.txts,buf(40,8))
end


-- -------------------------- --
-- Trivial Tunneling Protocol --
-- -------------------------- --
jttp_proto = Proto("jTTP","jTrivial Tunneling Protocol")

local jttpf = jttp_proto.fields
jttpf.ttype  = ProtoField.uint8("jttp.type","type",base.DEC,tnp_proto_tunnel_types)
jttpf.tprio  = ProtoField.uint8("jttp.prio","priority",base.DEC,tnp_proto_tunnel_priority)
jttpf.tprot  = ProtoField.uint8("jttp.proto","protocol",base.DEC,tnp_proto_protocols)
jttpf.tqueue = ProtoField.uint8("jttp.queue","queue",base.DEC)
jttpf.tiflidx= ProtoField.uint32("jttp.ifl_idx","ifl_index",base.HEX)
jttpf.tlen   = ProtoField.uint16("jttp.length","length",base.DEC)
jttpf.tnh_dm = ProtoField.uint16("jttp.nh_dstmask","nh_destmask",base.HEX)
jttpf.tnh_idx= ProtoField.uint32("jttp.nh_idx","nh_index",base.HEX)
jttpf.thint  = ProtoField.uint32("jttp.hint","hint",base.HEX)
jttpf.thno_key_lookup = ProtoField.uint32("jttp.hint.no_key_lookup","no_key_lookup",nil,nil,0x00000001)
jttpf.thsample = ProtoField.uint32("jttp.hint.sample","sample",nil,nil,0x00000002)
jttpf.thl2_multicast = ProtoField.uint32("jttp.hint.l2_multicast","l2_multicast",nil,nil,0x00000004)
jttpf.thl3_mtu_exceed = ProtoField.uint32("jttp.hint.l3_mtu_exceed","l3_mtu_exceed",nil,nil,0x00000008)
jttpf.thselect_fc = ProtoField.uint32("jttp.hint.select_fc","select_fc",nil,nil,0x00000010)
jttpf.thl3_reject = ProtoField.uint32("jttp.hint.l3_reject","l3_reject",nil,nil,0x00000080)
jttpf.thinput_pkt_type_eoam = ProtoField.uint32("jttp.hint.input_pkt_type_eoam","input_pkt_type_eoam",nil,nil,0x00000800)
jttpf.thiif_translated_from_irb = ProtoField.uint32("jttp.hint.iif_translated_from_irb","iif_translated_from_irb",nil,nil,0x00004000)
jttpf.thttp_tlv = ProtoField.uint32("jttp.hint.ttp_tlv","ttp_tlv",nil,nil,0x00008000)
jttpf.thstacked_ifl = ProtoField.uint32("jttp.hint.stacked_ifl","stacked_ifl",nil,nil,0x00010000)
jttpf.thinput_re_bypass_lookup = ProtoField.uint32("jttp.hint.input_re_bypass_lookup","input_re_bypass_lookup",nil,nil,0x00040000)
jttpf.thstrip_cookie_bytes = ProtoField.uint32("jttp.hint.strip_cookie_bytes","strip_cookie_bytes",nil,nil,0x00080000)
jttpf.thautosense = ProtoField.uint32("jttp.hint.autosense","autosense",nil,nil,0x00100000)
jttpf.thrsd_picpeer0 = ProtoField.uint32("jttp.hint.rsd_picpeer0","rsd_picpeer0",nil,nil,0x00200000)
jttpf.thrsd_picpeer1 = ProtoField.uint32("jttp.hint.rsd_picpeer1","rsd_picpeer1",nil,nil,0x00400000)
jttpf.thrsd_picpeer2 = ProtoField.uint32("jttp.hint.rsd_picpeer2","rsd_picpeer2",nil,nil,0x00800000)
jttpf.thl4_tcp = ProtoField.uint32("jttp.hint.l4_tcp","l4_tcp",nil,nil,0x01000000)
jttpf.thbd_index_present = ProtoField.uint32("jttp.hint.bd_index_present","bd_index_present",nil,nil,0x02000000)
jttpf.thrsd_picpeer3 = ProtoField.uint32("jttp.hint.rsd_picpeer3","rsd_picpeer3",nil,nil,0x04000000)
jttpf.thselect_q = ProtoField.uint32("jttp.hint.select_q","select_q",nil,nil,0x10000000)
jttpf.thkeepalive = ProtoField.uint32("jttp.hint.keepalive","keepalive",nil,nil,0x40000000)
jttpf.thdebug = ProtoField.uint32("jttp.hint.debug","debug",nil,nil,0x80000000)
-- jttpf.tdata  = ProtoField.bytes("jttp.data","data")

function jttp_proto.dissector(buf,pinfo,tree,tnpver)

      -- this is needed if we are called from inside TNP
      -- otherwise assume version 3
      if tnpver == nil then
        tnpver = 3
      end

      pinfo.cols.protocol = "jTTP"

      local tunnel = tree:add(jttp_proto,buf(),"Trivial Tunneling protocol")

      local offset = 0
      local tunneltype = "unknown"
      if tnp_proto_tunnel_types[buf(offset,1)] ~= nil then
        tunneltype = tnp_proto_tunnel_types[buf(offset,1)]
      end

      local ttptype = buf(offset,1):uint()
      tunnel:add(jttpf.ttype,buf(offset,1))
      tunnel:add(jttpf.tprio,buf(offset+1,1))
      tunnel:add(jttpf.tprot,buf(offset+2,1))

      local ttpproto = buf(offset+2,1):uint()
      local ttpprotoname = "???"

      if tnp_proto_protocols[ttpproto] ~= nil then
        ttpprotoname = tnp_proto_protocols[ttpproto]
      end
      pinfo.cols.protocol:append("(" .. ttpprotoname .. ")")

      tunnel:add(jttpf.tqueue,buf(offset+3,1))
      if tnpver == 1 then
        tunnel:add(jttpf.tiflidx,buf(offset+4,2))
        offset = offset + 2
      else
        tunnel:add(jttpf.tiflidx,buf(offset+4,4))
      end
      tunnel:add(jttpf.tlen,buf(offset+8,2))
      tunnel:add(jttpf.tnh_dm,buf(offset+10,2))
      if tnpver == 1 then
        tunnel:add(jttpf.tnh_idx,buf(offset+12,2))
        offset = offset + 2
      else
        tunnel:add(jttpf.tnh_idx,buf(offset+12,4))
      end

      local thint = tunnel:add(jttpf.thint,buf(offset+16,4))
      local thintoffset = offset + 16
      thint:add(jttpf.thno_key_lookup,buf(thintoffset,4))
      thint:add(jttpf.thsample,buf(thintoffset,4))
      thint:add(jttpf.thl2_multicast,buf(thintoffset,4))
      thint:add(jttpf.thl3_mtu_exceed,buf(thintoffset,4))
      thint:add(jttpf.thselect_fc,buf(thintoffset,4))
      thint:add(jttpf.thl3_reject,buf(thintoffset,4))
      thint:add(jttpf.thinput_pkt_type_eoam,buf(thintoffset,4))
      thint:add(jttpf.thiif_translated_from_irb,buf(thintoffset,4))
      thint:add(jttpf.thttp_tlv,buf(thintoffset,4))
      thint:add(jttpf.thstacked_ifl,buf(thintoffset,4))
      thint:add(jttpf.thinput_re_bypass_lookup,buf(thintoffset,4))
      thint:add(jttpf.thstrip_cookie_bytes,buf(thintoffset,4))
      thint:add(jttpf.thautosense,buf(thintoffset,4))
      thint:add(jttpf.thrsd_picpeer0,buf(thintoffset,4))
      thint:add(jttpf.thrsd_picpeer1,buf(thintoffset,4))
      thint:add(jttpf.thrsd_picpeer2,buf(thintoffset,4))
      thint:add(jttpf.thl4_tcp,buf(thintoffset,4))
      thint:add(jttpf.thbd_index_present,buf(thintoffset,4))
      thint:add(jttpf.thrsd_picpeer3,buf(thintoffset,4))
      thint:add(jttpf.thselect_q,buf(thintoffset,4))
      thint:add(jttpf.thkeepalive,buf(thintoffset,4))
      thint:add(jttpf.thdebug,buf(thintoffset,4))

      -- tunnel:add(jttpf.tdata,buf(offset+20))

      local inside_proto = buf(offset+2,1):uint()

      local inside_dis = Dissector.get ("data")
      local cookie = 0

      if inside_proto == 2 or inside_proto == 3  then
        inside_dis = Dissector.get ("ip")
      elseif inside_proto == 6 or inside_proto == 7 then
        inside_dis = Dissector.get ("ip6")
      elseif inside_proto == 0 then
        -- TODO: this is one huuuuuugee hack, this has to be calculated and
        -- not guessed, no idea how to do it currently
        if (buf(offset,1):uint() == 1 ) then
          inside_dis = Dissector.get ("eth")
        elseif (buf(offset,1):uint() == 2 ) then
          if (buf(offset+46,1):uint() == 69) then
            inside_dis = Dissector.get ("eth")
            cookie = 12
          elseif (buf(offset+28,1):uint() == 69) then
            inside_dis = Dissector.get ("ip")
            cookie = 8
          elseif (buf(offset+38,1):uint() == 69) then
            inside_dis = Dissector.get ("eth")
            cookie = 4
          elseif (buf(offset+44,1):uint() == 69) then
            inside_dis = Dissector.get ("ip")
            cookie = 24
          elseif (buf(offset+40,1):uint() == 69) then
            inside_dis = Dissector.get ("eth")
            cookie = 6
          else
            inside_dis = Dissector.get ("eth")
            cookie = 12 -- 12
          end
        end
      elseif inside_proto == 4 or inside_proto == 5 or inside_proto == 8 or inside_proto == 32 then
        inside_dis = Dissector.get ("mpls")
      elseif inside_proto == 10 then
        inside_dis = Dissector.get ("clnp")
      elseif inside_proto == 9 then
        inside_dis = Dissector.get ("arp")
      end
      inside_dis:call (buf(offset+20+cookie):tvb(), pinfo, tree)
end

-- This is a internal ethertype, it looks like it just adds additional two bytes
-- data before the correct ethertype

lclexpjnpr_proto = Proto("LEE1","Local Experimental EtherType1")

function lclexpjnpr_proto.dissector(buf,pinfo,tree)
  if (tostring(buf(0,2)) == "8850") then
    tnp_proto.dissector:call (buf(2):tvb(), pinfo, tree)
--  elseif (tostring(buf(0,2)) == "0800") then
--    inside_dis = Dissector.get ("ip")
--    inside_dis:call (buf(2):tvb(), pinfo, tree)
  end
end

-- binds to the wireshark dissector table
ether_table = DissectorTable.get("ethertype")
ether_table:add(0x8850,tnp_proto)
ether_table:add(0x88b5,lclexpjnpr_proto)

ip_table = DissectorTable.get("ip.proto")
ip_table:add(84,jttp_proto)
