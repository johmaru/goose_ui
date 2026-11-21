"""Equivalent Python Tkinter memory & startup/layout/render benchmark."""
import ctypes
import json
import sys
import time
import tkinter as tk
from tkinter import ttk


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [
        ("cb", ctypes.c_ulong),
        ("PageFaultCount", ctypes.c_ulong),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
        ("PrivateUsage", ctypes.c_size_t),
    ]


def read_mem():
    pmc = PROCESS_MEMORY_COUNTERS_EX()
    pmc.cb = ctypes.sizeof(pmc)
    k32 = ctypes.windll.kernel32
    k32.K32GetProcessMemoryInfo(ctypes.c_void_p(-1), ctypes.byref(pmc), pmc.cb)
    return pmc


def main():
    t_start = time.perf_counter()
    count = 0
    if "--count" in sys.argv:
        idx = sys.argv.index("--count")
        if idx + 1 < len(sys.argv):
            count = int(sys.argv[idx + 1])

    root = tk.Tk()
    root.title("Tkinter Memory Bench")
    root.geometry("900x640")

    main_frame = ttk.Frame(root, padding=10)
    main_frame.pack(fill="both", expand=True)

    status = ttk.Label(root, text="Benchmark running", anchor="w")
    status.pack(fill="x", side="bottom")

    created = 0
    total_widgets = 3
    keep_vars = []

    if count > 0:
        canvas = tk.Canvas(main_frame, highlightthickness=0)
        scroll = ttk.Scrollbar(main_frame, orient="vertical", command=canvas.yview)
        inner = ttk.Frame(canvas)
        canvas.create_window((0, 0), window=inner, anchor="nw")
        canvas.configure(yscrollcommand=scroll.set)
        canvas.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        total_widgets += 3

        rows = (count + 4) // 5
        for r in range(rows):
            row = ttk.Frame(inner)
            row.pack(fill="x", pady=2)
            total_widgets += 1
            if created < count:
                ttk.Label(row, text=f"Row {r}").pack(side="left", padx=3)
                created += 1
                total_widgets += 1
            if created < count:
                ent = ttk.Entry(row)
                ent.insert(0, f"Item {r}")
                ent.pack(side="left", fill="x", expand=True, padx=3)
                created += 1
                total_widgets += 1
            if created < count:
                v = tk.BooleanVar(value=(r % 2) == 0)
                keep_vars.append(v)
                ttk.Checkbutton(row, text="Active", variable=v).pack(side="left", padx=3)
                created += 1
                total_widgets += 1
            if created < count:
                pb = ttk.Progressbar(row, maximum=100, value=(r * 7) % 100, length=90)
                pb.pack(side="left", padx=3)
                created += 1
                total_widgets += 1
            if created < count:
                ttk.Button(row, text="Action").pack(side="left", padx=3)
                created += 1
                total_widgets += 1

    t_built = time.perf_counter()
    root.update_idletasks()
    t_laid_out = time.perf_counter()
    root.update()
    t_rendered = time.perf_counter()

    pmc = read_mem()
    print(json.dumps({
        "framework": "python_tkinter",
        "controls": created,
        "total_widgets": total_widgets,
        "private_bytes": pmc.PrivateUsage,
        "working_set": pmc.WorkingSetSize,
        "peak_working_set": pmc.PeakWorkingSetSize,
        "build_ms": round((t_built - t_start) * 1000.0, 2),
        "layout_ms": round((t_laid_out - t_built) * 1000.0, 2),
        "render_ms": round((t_rendered - t_laid_out) * 1000.0, 2),
        "total_ms": round((t_rendered - t_start) * 1000.0, 2),
    }))
    root.destroy()


if __name__ == "__main__":
    main()
