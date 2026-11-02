-- Qt 6 project template (Widgets or Qt Quick/QML).

local editor = require("scaffold.templates.editor")
local fs = require("scaffold.core.filesystem")
local standards = require("scaffold.templates.standards")

-- Qt headers are only known after CMake configure (compile_commands.json), but
-- on Arch/Debian they live in predictable places; include the ones that exist so
-- clangd is useful from the first :edit.
local function qt_includes()
  local dirs = {}
  for _, dir in ipairs({
    "/usr/include/qt6",
    "/usr/include/qt6/QtCore",
    "/usr/include/qt6/QtGui",
    "/usr/include/qt6/QtWidgets",
    "/usr/include/qt6/QtQml",
    "/usr/include/qt6/QtQuick",
    "/usr/include/x86_64-linux-gnu/qt6",
    "/usr/include/x86_64-linux-gnu/qt6/QtCore",
  }) do
    if fs.is_dir(dir) then
      dirs[#dirs + 1] = dir
    end
  end
  return dirs
end

local function cmake_lists(ctx)
  local standard = ctx.standard or "20"
  local common = table.concat({
    "cmake_minimum_required(VERSION 3.21)",
    ("project(%s VERSION 0.1.0 LANGUAGES CXX)"):format(ctx.project_slug),
    "",
    ("set(CMAKE_CXX_STANDARD %s)"):format(standard),
    "set(CMAKE_CXX_STANDARD_REQUIRED ON)",
    "set(CMAKE_CXX_EXTENSIONS OFF)",
    "set(CMAKE_EXPORT_COMPILE_COMMANDS ON)",
    "set(CMAKE_AUTOMOC ON)",
    "set(CMAKE_AUTORCC ON)",
    "set(CMAKE_AUTOUIC ON)",
    "",
  }, "\n")

  if ctx.ui == "qml" then
    return common .. table.concat({
      "find_package(Qt6 REQUIRED COMPONENTS Quick)",
      "",
      ("qt_add_executable(%s src/main.cpp)"):format(ctx.project_slug),
      ("qt_add_qml_module(%s"):format(ctx.project_slug),
      ("  URI %s"):format(ctx.project_module),
      "  VERSION 1.0",
      "  QML_FILES Main.qml",
      ")",
      ("target_link_libraries(%s PRIVATE Qt6::Quick)"):format(ctx.project_slug),
      "",
    }, "\n")
  end

  return common .. table.concat({
    "find_package(Qt6 REQUIRED COMPONENTS Widgets)",
    "",
    ("qt_add_executable(%s"):format(ctx.project_slug),
    "  src/main.cpp",
    "  src/mainwindow.cpp",
    "  src/mainwindow.h",
    ")",
    ("target_include_directories(%s PRIVATE src)"):format(ctx.project_slug),
    ("target_link_libraries(%s PRIVATE Qt6::Widgets)"):format(ctx.project_slug),
    "",
  }, "\n")
end

local function main_widgets()
  return table.concat({
    '#include <QApplication>',
    "",
    '#include "mainwindow.h"',
    "",
    "int main(int argc, char *argv[]) {",
    "  QApplication app(argc, argv);",
    "  MainWindow window;",
    "  window.show();",
    "  return app.exec();",
    "}",
    "",
  }, "\n")
end

local function mainwindow_h()
  return table.concat({
    "#pragma once",
    "",
    "#include <QMainWindow>",
    "",
    "class MainWindow : public QMainWindow {",
    "  Q_OBJECT",
    "",
    "public:",
    "  explicit MainWindow(QWidget *parent = nullptr);",
    "};",
    "",
  }, "\n")
end

local function mainwindow_cpp(ctx)
  return table.concat({
    '#include "mainwindow.h"',
    "",
    "#include <QLabel>",
    "#include <QPushButton>",
    "#include <QVBoxLayout>",
    "",
    "MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {",
    "  auto *central = new QWidget(this);",
    "  auto *layout = new QVBoxLayout(central);",
    "  auto *label = new QLabel(tr(\"Hello from Qt Widgets\"), central);",
    "  auto *button = new QPushButton(tr(\"Quit\"), central);",
    "",
    "  connect(button, &QPushButton::clicked, this, &QWidget::close);",
    "",
    "  layout->addWidget(label);",
    "  layout->addWidget(button);",
    "  setCentralWidget(central);",
    ("  setWindowTitle(tr(\"%s\"));"):format(ctx.project_name),
    "  resize(480, 240);",
    "}",
    "",
  }, "\n")
end

local function main_qml(ctx)
  return table.concat({
    "#include <QGuiApplication>",
    "#include <QQmlApplicationEngine>",
    "",
    "int main(int argc, char *argv[]) {",
    "  QGuiApplication app(argc, argv);",
    "",
    "  QQmlApplicationEngine engine;",
    "  QObject::connect(",
    "      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,",
    "      []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);",
    ("  engine.loadFromModule(\"%s\", \"Main\");"):format(ctx.project_module),
    "",
    "  return app.exec();",
    "}",
    "",
  }, "\n")
end

local function main_qml_file(ctx)
  return table.concat({
    "import QtQuick",
    "import QtQuick.Controls",
    "",
    "ApplicationWindow {",
    "    visible: true",
    "    width: 800",
    "    height: 600",
    ("    title: qsTr(\"%s\")"):format(ctx.project_name),
    "",
    "    Column {",
    "        anchors.centerIn: parent",
    "        spacing: 16",
    "",
    "        Label {",
    "            text: qsTr(\"Hello from Qt Quick\")",
    "            font.pixelSize: 24",
    "        }",
    "",
    "        Button {",
    "            text: qsTr(\"Quit\")",
    "            onClicked: Qt.quit()",
    "        }",
    "    }",
    "}",
    "",
  }, "\n")
end

local function readme(ctx)
  local qt = ctx.ui == "qml" and "Qt Quick (QML)" or "Qt Widgets"
  return table.concat({
    "# {{project_name}}",
    "",
    ("%s project generated by Scaffold.nvim (C++%s, CMake, Qt 6)."):format(qt, ctx.standard or "20"),
    "",
    "## Requirements",
    "",
    "- Qt 6 development files",
    "- CMake 3.21+ and Ninja",
    "",
    "Arch Linux: `sudo pacman -S qt6-base" .. (ctx.ui == "qml" and " qt6-declarative" or "") .. " cmake ninja`",
    "Debian/Ubuntu: `sudo apt install qt6-base-dev" .. (ctx.ui == "qml" and " qt6-declarative-dev" or "") .. " cmake ninja-build`",
    "",
    "## Build and run",
    "",
    "```sh",
    "cmake -S . -B build -G Ninja",
    "cmake --build build",
    ("./build/%s"):format(ctx.project_slug),
    "```",
    "",
    "Run `:ScaffoldBuild` once inside the project: it configures CMake, which",
    "produces `compile_commands.json` with the real Qt include paths.",
    "",
  }, "\n")
end

return {
  templates = {
    {
      id = "cpp-qt",
      name = "Qt 6 Application",
      language = "cpp",
      version = 1,
      description = "A Qt 6 desktop application: Widgets or Qt Quick/QML.",
      validate_options = standards.check,
      build_systems = { "cmake" },
      runtime_options = { "g++", "clang++" },
      default_runtime = "g++",
      default_build_system = "cmake",
      requires = { "cmake", "ninja" },
      options = {
        standard = {
          type = "select",
          label = "C++ standard",
          values = { "17", "20", "23", "26" },
          default = "20",
        },
        ui = {
          type = "select",
          label = "UI toolkit",
          values = { "widgets", "qml" },
          default = "widgets",
        },
      },
      files = {
        ["CMakeLists.txt"] = cmake_lists,
        ["src/main.cpp"] = function(ctx)
          if ctx.ui == "qml" then
            return main_qml(ctx)
          end
          return main_widgets()
        end,
        ["src/mainwindow.h"] = function(ctx)
          if ctx.ui == "qml" then
            return nil
          end
          return mainwindow_h()
        end,
        ["src/mainwindow.cpp"] = function(ctx)
          if ctx.ui == "qml" then
            return nil
          end
          return mainwindow_cpp(ctx)
        end,
        ["Main.qml"] = function(ctx)
          if ctx.ui ~= "qml" then
            return nil
          end
          return main_qml_file(ctx)
        end,
        ["compile_flags.txt"] = function(ctx)
          local includes = qt_includes()
          return editor.compile_flags("c++" .. (ctx.standard or "20"), includes)
        end,
        [".clangd"] = function(ctx)
          return editor.clangd("c++" .. (ctx.standard or "20"))
        end,
        [".gitignore"] = table.concat({
          "/build/",
          "*.user",
          "compile_commands.json",
          "",
        }, "\n"),
        ["README.md"] = readme,
      },
      commands = {
        configure = { "cmake", "-S", ".", "-B", "build", "-G", "Ninja", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" },
        build = { "cmake", "--build", "build" },
        run = function(ctx)
          return { "./build/" .. ctx.project_slug }
        end,
        clean = { "cmake", "--build", "build", "--target", "clean" },
      },
      install_commands = {},
    },
  },
}
