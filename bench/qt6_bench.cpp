// Equivalent Qt 6 Widgets memory & startup/layout/render benchmark.
// Build with MinGW + Qt 6 (automated by bench/run_bench.ps1).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>

#include <QApplication>
#include <QCheckBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QProgressBar>
#include <QPushButton>
#include <QScrollArea>
#include <QStatusBar>
#include <QVBoxLayout>
#include <QWidget>

#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char **argv) {
    LARGE_INTEGER freq, t_start, t_built, t_laid_out, t_rendered;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t_start);

    int count = 0;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--count") == 0 && i + 1 < argc) {
            count = std::atoi(argv[++i]);
        }
    }

    QApplication app(argc, argv);
    QMainWindow win;
    win.setWindowTitle("Qt6 Widgets Memory Bench");
    win.resize(900, 640);
    win.statusBar()->showMessage("Benchmark running");

    auto *central = new QWidget(&win);
    auto *rootLayout = new QVBoxLayout(central);
    rootLayout->setContentsMargins(10, 10, 10, 10);
    rootLayout->setSpacing(6);
    win.setCentralWidget(central);

    int created_controls = 0;
    int total_widgets = 2; // window + central

    if (count > 0) {
        auto *scroll = new QScrollArea(central);
        scroll->setWidgetResizable(true);
        auto *content = new QWidget();
        auto *vbox = new QVBoxLayout(content);
        vbox->setContentsMargins(6, 6, 6, 6);
        vbox->setSpacing(4);
        total_widgets += 2;

        int rows = (count + 4) / 5;
        for (int r = 0; r < rows; ++r) {
            auto *rowWidget = new QWidget(content);
            auto *hbox = new QHBoxLayout(rowWidget);
            hbox->setContentsMargins(0, 0, 0, 0);
            hbox->setSpacing(6);
            total_widgets += 1;

            if (created_controls < count) {
                hbox->addWidget(new QLabel(QString("Row %1").arg(r), rowWidget));
                created_controls++; total_widgets++;
            }
            if (created_controls < count) {
                auto *ed = new QLineEdit(QString("Item %1").arg(r), rowWidget);
                ed->setPlaceholderText("Value");
                hbox->addWidget(ed, 1);
                created_controls++; total_widgets++;
            }
            if (created_controls < count) {
                auto *cb = new QCheckBox("Active", rowWidget);
                cb->setChecked((r % 2) == 0);
                hbox->addWidget(cb);
                created_controls++; total_widgets++;
            }
            if (created_controls < count) {
                auto *pb = new QProgressBar(rowWidget);
                pb->setRange(0, 100);
                pb->setValue((r * 7) % 100);
                pb->setFixedWidth(90);
                hbox->addWidget(pb);
                created_controls++; total_widgets++;
            }
            if (created_controls < count) {
                hbox->addWidget(new QPushButton("Action", rowWidget));
                created_controls++; total_widgets++;
            }
            vbox->addWidget(rowWidget);
        }
        scroll->setWidget(content);
        rootLayout->addWidget(scroll, 1);
    }

    QueryPerformanceCounter(&t_built);

    win.show();
    app.processEvents();
    QueryPerformanceCounter(&t_laid_out);

    win.repaint();
    app.processEvents();
    QueryPerformanceCounter(&t_rendered);

    PROCESS_MEMORY_COUNTERS_EX pmc;
    std::memset(&pmc, 0, sizeof(pmc));
    pmc.cb = sizeof(pmc);
    GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&pmc), sizeof(pmc));

    double build_ms = double(t_built.QuadPart - t_start.QuadPart) * 1000.0 / double(freq.QuadPart);
    double layout_ms = double(t_laid_out.QuadPart - t_built.QuadPart) * 1000.0 / double(freq.QuadPart);
    double render_ms = double(t_rendered.QuadPart - t_laid_out.QuadPart) * 1000.0 / double(freq.QuadPart);
    double total_ms = double(t_rendered.QuadPart - t_start.QuadPart) * 1000.0 / double(freq.QuadPart);

    std::printf(
        "{\"framework\":\"qt6_widgets\",\"controls\":%d,\"total_widgets\":%d,"
        "\"private_bytes\":%llu,\"working_set\":%llu,\"peak_working_set\":%llu,"
        "\"build_ms\":%.2f,\"layout_ms\":%.2f,\"render_ms\":%.2f,\"total_ms\":%.2f}\n",
        created_controls,
        total_widgets,
        static_cast<unsigned long long>(pmc.PrivateUsage),
        static_cast<unsigned long long>(pmc.WorkingSetSize),
        static_cast<unsigned long long>(pmc.PeakWorkingSetSize),
        build_ms, layout_ms, render_ms, total_ms
    );
    std::fflush(stdout);
    return 0;
}
