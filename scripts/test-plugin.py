#!/usr/bin/env python3
"""Exercise the real compiled C ABI, without starting or calling a model provider."""
import base64
import ctypes as c
import json
import sys

class Buffer(c.Structure):
    _fields_ = [('ptr', c.c_void_p), ('len', c.c_size_t)]

Invoke = c.CFUNCTYPE(c.c_int, c.c_char_p, c.c_void_p, c.c_size_t, c.POINTER(Buffer))
Free = c.CFUNCTYPE(None, c.c_void_p, c.c_size_t)
Shutdown = c.CFUNCTYPE(None)

class Host(c.Structure):
    _fields_ = [('abi_version', c.c_uint32), ('ctx', c.c_void_p), ('call', c.c_void_p), ('free', c.c_void_p)]

class Plugin(c.Structure):
    _fields_ = [('abi_version', c.c_uint32), ('call', Invoke), ('free', Free), ('shutdown', Shutdown)]

lib = c.CDLL(sys.argv[1])
lib.cliproxy_plugin_init.argtypes = [c.POINTER(Host), c.POINTER(Plugin)]
lib.cliproxy_plugin_init.restype = c.c_int
host, plugin = Host(1, None, None, None), Plugin()
assert lib.cliproxy_plugin_init(c.byref(host), c.byref(plugin)) == 0
assert plugin.abi_version == 1

def call(method):
    buf = Buffer()
    assert plugin.call(method.encode(), None, 0, c.byref(buf)) == 0
    try:
        return json.loads(c.string_at(buf.ptr, buf.len))
    finally:
        plugin.free(buf.ptr, buf.len)

registration = call('plugin.register')['result']
assert registration['capabilities'] == {'management_api': True}
assert registration['metadata']['Name'] == 'CPAMC Menu Bar'
assert call('plugin.reconfigure') == call('plugin.register')
routes = call('management.register')['result']
assert 'routes' not in routes
assert routes['resources'][0]['Path'] == '/menubar'
response = call('management.handle')['result']
assert response['StatusCode'] == 200
html = base64.b64decode(response['Body']).decode()
assert 'cpamc-menubar://subscriptions' in html
assert '$TOKEN$' not in html and 'localStorage' not in html
assert call('model.execute')['ok'] is False
bad = Host(0, None, None, None)
assert lib.cliproxy_plugin_init(c.byref(bad), c.byref(Plugin())) != 0
plugin.shutdown()
print('Plugin ABI/resource checks passed; no model/auth/routing hooks registered.')
