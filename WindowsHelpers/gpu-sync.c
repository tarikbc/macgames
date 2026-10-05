/* gpu-sync.exe [--watch <program> [--wait-seconds N] | --list]
 *
 * Age of Mythology: Retold checks the GPU vendor in the registry, under
 * HKLM\Software\Microsoft\DirectX\<adapter>, not through DXGI. Wine fills those keys
 * with the Mac's GPU, while D3DMetal's DXGI reports another vendor, so the game warns
 * that the GPU is unsupported. This helper copies DXGI's VendorId and DeviceId into the
 * key of the same adapter.
 *
 * Wine can create those keys again while it runs, so --watch keeps them in step until
 * the program has started and exited, or until N seconds (300 by default) pass without it.
 * --list prints the DXGI adapters and the DirectX keys without changing anything.
 * Exit codes: 0 done, 2 no DXGI, 3 no DirectX key, 4 the program never started, 10 usage. */
#define COBJMACROS
#include "helpers.h"
#include <dxgi.h>

static const wchar_t *directx = L"Software\\Microsoft\\DirectX";

static int listing;

struct adapter { LUID luid; UINT vendor, device; };
struct key { wchar_t name[256]; LUID luid; DWORD vendor, device; };

static int same_luid(LUID a, LUID b) { return a.LowPart == b.LowPart && a.HighPart == b.HighPart; }

static void write_ids(HKEY root, const struct key *k, const struct adapter *a) {
    if (k->vendor == a->vendor && k->device == a->device) return;
    HKEY key;
    if (RegOpenKeyExW(root, k->name, 0, KEY_SET_VALUE, &key)) return;
    DWORD vendor = a->vendor, device = a->device;
    RegSetValueExW(key, L"VendorId", 0, REG_DWORD, (const BYTE *)&vendor, sizeof vendor);
    RegSetValueExW(key, L"DeviceId", 0, REG_DWORD, (const BYTE *)&device, sizeof device);
    RegCloseKey(key);
    say("Set %ls to vendor %04x device %04x (was %04lx %04lx).", k->name, a->vendor, a->device, k->vendor, k->device);
}

/* One pass over DXGI's hardware adapters and the DirectX keys. A key belongs to the
 * adapter with the same LUID. D3DMetal builds its LUID from the Metal device instead of
 * Wine's, so when nothing matches and there is one adapter and one key, as on every
 * Apple silicon Mac, those two belong together. Returns 0, 2 or 3 like the exit codes. */
static int sync_once(void) {
    /* Asking for a display device first lets Wine finish its display setup, which creates the keys. */
    DISPLAY_DEVICEW display = { .cb = sizeof display };
    EnumDisplayDevicesW(NULL, 0, &display, 0);
    IDXGIFactory1 *factory = NULL;
    if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory))) return 2;
    struct adapter adapters[8];
    int adapterCount = 0;
    IDXGIAdapter1 *adapter;
    for (UINT i = 0; adapterCount < 8 && IDXGIFactory1_EnumAdapters1(factory, i, &adapter) != DXGI_ERROR_NOT_FOUND; i++) {
        DXGI_ADAPTER_DESC1 desc;
        HRESULT hr = IDXGIAdapter1_GetDesc1(adapter, &desc);
        IDXGIAdapter1_Release(adapter);
        if (FAILED(hr) || (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) || !desc.VendorId) continue;
        adapters[adapterCount++] = (struct adapter){ desc.AdapterLuid, desc.VendorId, desc.DeviceId };
        if (listing)
            say("adapter %ls: luid %08lx:%08lx vendor %04x device %04x", desc.Description, desc.AdapterLuid.HighPart,
                desc.AdapterLuid.LowPart, desc.VendorId, desc.DeviceId);
    }
    IDXGIFactory1_Release(factory);

    HKEY root;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, directx, 0, KEY_READ, &root)) return 3;
    static struct key keys[16];
    int keyCount = 0;
    for (DWORD i = 0, length = 256; keyCount < 16 && RegEnumKeyExW(root, i, keys[keyCount].name, &length, NULL, NULL, NULL, NULL) == ERROR_SUCCESS;
         i++, length = 256) {
        struct key *k = &keys[keyCount];
        HKEY key;
        if (RegOpenKeyExW(root, k->name, 0, KEY_READ, &key)) continue;
        DWORD type = 0, size = sizeof k->luid, vs = sizeof k->vendor, ds = sizeof k->device;
        k->vendor = k->device = 0;
        int ok = !RegQueryValueExW(key, L"AdapterLuid", NULL, &type, (BYTE *)&k->luid, &size) && type == REG_QWORD && size == sizeof k->luid;
        RegQueryValueExW(key, L"VendorId", NULL, NULL, (BYTE *)&k->vendor, &vs);
        RegQueryValueExW(key, L"DeviceId", NULL, NULL, (BYTE *)&k->device, &ds);
        RegCloseKey(key);
        if (!ok) continue;
        if (listing)
            say("  key %ls: luid %08lx:%08lx vendor %04lx device %04lx", k->name, k->luid.HighPart, k->luid.LowPart, k->vendor, k->device);
        keyCount++;
    }

    int matched = 0;
    for (int a = 0; a < adapterCount; a++)
        for (int k = 0; k < keyCount; k++)
            if (same_luid(adapters[a].luid, keys[k].luid)) { matched++; if (!listing) write_ids(root, &keys[k], &adapters[a]); }
    if (!matched && adapterCount == 1 && keyCount == 1) {
        matched = 1;
        if (!listing) write_ids(root, &keys[0], &adapters[0]);
    }
    RegCloseKey(root);
    return matched ? 0 : 3;
}

int wmain(int argc, wchar_t **argv) {
    const wchar_t *program = option(argc, argv, L"--watch");
    listing = argc == 2 && wcscmp(argv[1], L"--list") == 0;
    if (argc > 1 && !program && !listing) return 10;
    int status = sync_once();
    if (!program) return status;

    HKEY root;
    HANDLE changed = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!changed || RegOpenKeyExW(HKEY_LOCAL_MACHINE, directx, 0, KEY_NOTIFY, &root)) return 3;
    DWORD filter = REG_NOTIFY_CHANGE_NAME | REG_NOTIFY_CHANGE_LAST_SET;
    RegNotifyChangeKeyValue(root, TRUE, filter, changed, TRUE);
    DWORD deadline = GetTickCount() + wait_seconds(argc, argv, 300) * 1000;
    int seen = 0;
    say("Keeping the GPU keys in step for %ls.", program);
    for (;;) {
        if (WaitForSingleObject(changed, 500) == WAIT_OBJECT_0) {
            RegNotifyChangeKeyValue(root, TRUE, filter, changed, TRUE);
            sync_once();
        }
        if (program_running(program)) seen = 1;
        else if (seen) break;
        else if ((LONG)(deadline - GetTickCount()) <= 0) { say("%ls did not start.", program); status = 4; break; }
    }
    RegCloseKey(root);
    CloseHandle(changed);
    return seen ? 0 : status;
}
