#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/wait.h>
#include <vhpidirect_user.h>

int run_command(const struct vhpidirect_array*);

int run_command(const struct vhpidirect_array *data) {
  size_t data_len = data->range->len;
  const char *cmd = data->data;

  if (data_len > 0) {
    return system(cmd);
  }
  return -1;
}

int bg_process_run(const struct vhpidirect_array *shell_expr) {
  size_t data_len = shell_expr->range->len;
  const char *cmd = shell_expr->data;

  int pid = fork();
  if (pid < 0)
    return -1;

  if (pid == 0) {
    // In child
    execlp("bash", "bash", "-c", cmd, NULL);
    exit(-1);
  }

  // In parent
  return pid;
}


int bg_process_wait(int pid) {
  int st = 0;
  int ret = waitpid(pid, &st, WNOHANG | WUNTRACED | WCONTINUED);

  // Fails
  if (ret < 0)
    return -1;

  // No process changed
  if (ret == 0)
    return -1;

  // Not our process
  if (ret != pid)
    return -1;

  // Not exited
  if (!WIFEXITED(st))
    return -1;

  return WEXITSTATUS(st);
}


