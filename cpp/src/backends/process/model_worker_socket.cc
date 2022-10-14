#include <iostream>
#include <memory>
#include <gflags/gflags.h>
#include <filesystem>

#include "src/utils/logging.hh"
#include "src/backends/process/model_worker.hh"

DEFINE_string(sock_type, "tcp", "socket type");
DEFINE_string(sock_name, "", "socket name for uds");
DEFINE_string(host, "127.0.0.1", "");
DEFINE_string(port, "9000", "");
DEFINE_string(runtime_type, "LSP", "model runtime type");
DEFINE_string(device_type, "cpu", "cpu, or gpu");
// TODO: discuss multiple backends support
DEFINE_string(model_dir, "", "model path");
DEFINE_string(logger_config_path, "", "Logging config file path");

int main(int argc, char* argv[]) {
  gflags::ParseCommandLineFlags(&argc, &argv, true);
  // Default logging file path is relative to the program invocation path
  // in the build artifacts. No way of knowing before args are parsed
  // Setting it once the args are parsed
  if (FLAGS_logger_config_path.empty()) {
    FLAGS_logger_config_path = std::string() +
                               std::filesystem::canonical(gflags::ProgramInvocationName()).parent_path().c_str() +
                               PATH_SEPARATOR + ".." +
                               PATH_SEPARATOR + "resources" +
                               PATH_SEPARATOR + "logging.config";
  }
  torchserve::Logger::InitLogger(FLAGS_logger_config_path);

  torchserve::SocketServer server = torchserve::SocketServer::GetInstance();

  server.Initialize(FLAGS_sock_type, FLAGS_sock_name,
  FLAGS_host, FLAGS_port, FLAGS_runtime_type, FLAGS_device_type, FLAGS_model_dir);

  server.Run();

  gflags::ShutDownCommandLineFlags();
}