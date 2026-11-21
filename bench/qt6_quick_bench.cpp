// Equivalent Qt 6 Quick (QML, GPU-accelerated via Direct3D 11 RHI) memory benchmark.
// Provides a direct GPU-vs-GPU comparison against goose_ui's Direct2D backend.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>

#include <cstdio>
#include <cstdlib>
#include <cstring>

static const char *QML_SOURCE = R"QML(
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 900
    height: 640
    visible: true
    title: "Qt6 Quick GPU Memory Bench"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: benchRows > 0

            ColumnLayout {
                width: parent.width
                spacing: 4

                Repeater {
                    model: benchRows
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "Row " + index }
                        TextField { Layout.fillWidth: true; text: "Item " + index; placeholderText: "Value" }
                        CheckBox { text: "Active"; checked: (index % 2) === 0 }
                        ProgressBar { Layout.preferredWidth: 90; from: 0; to: 100; value: (index * 7) % 100 }
                        Button { text: "Action" }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: "Benchmark running"
        }
    }
}
)QML";

int main(int argc, char **argv) {
    LARGE_INTEGER freq, t_start, t_built, t_rendered;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t_start);

    int count = 0;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--count") == 0 && i + 1 < argc) {
            count = std::atoi(argv[++i]);
        }
    }
    int rows = (count > 0) ? ((count + 4) / 5) : 0;

    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("benchRows", rows);
    engine.loadData(QByteArray(QML_SOURCE));

    QueryPerformanceCounter(&t_built);

    if (engine.rootObjects().isEmpty()) {
        std::fprintf(stderr, "Failed to load QML\n");
        return 1;
    }

    auto *win = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    bool reported = false;
    auto report = [&]() {
        if (reported) return;
        reported = true;
        QueryPerformanceCounter(&t_rendered);

        PROCESS_MEMORY_COUNTERS_EX pmc;
        std::memset(&pmc, 0, sizeof(pmc));
        pmc.cb = sizeof(pmc);
        GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS *>(&pmc), sizeof(pmc));

        double build_ms = double(t_built.QuadPart - t_start.QuadPart) * 1000.0 / double(freq.QuadPart);
        double render_ms = double(t_rendered.QuadPart - t_built.QuadPart) * 1000.0 / double(freq.QuadPart);
        double total_ms = double(t_rendered.QuadPart - t_start.QuadPart) * 1000.0 / double(freq.QuadPart);

        std::printf(
            "{\"framework\":\"qt6_quick_gpu\",\"controls\":%d,\"total_widgets\":%d,"
            "\"private_bytes\":%llu,\"working_set\":%llu,\"peak_working_set\":%llu,"
            "\"build_ms\":%.2f,\"layout_ms\":0.00,\"render_ms\":%.2f,\"total_ms\":%.2f}\n",
            rows * 5,
            rows * 6 + 3,
            static_cast<unsigned long long>(pmc.PrivateUsage),
            static_cast<unsigned long long>(pmc.WorkingSetSize),
            static_cast<unsigned long long>(pmc.PeakWorkingSetSize),
            build_ms, render_ms, total_ms
        );
        std::fflush(stdout);
        app.quit();
    };

    if (win) {
        QObject::connect(win, &QQuickWindow::frameSwapped, &app, report, Qt::QueuedConnection);
    }
    // Fallback timeout in case frameSwapped isn't delivered.
    QTimer::singleShot(3000, &app, report);

    return app.exec();
}
