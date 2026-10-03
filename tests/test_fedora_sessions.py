#!/usr/bin/env python3
"""Bounded Fedora regressions: no real agents, installation or user-history writes.

Run: python3 -m unittest discover -s tests -p test_fedora_sessions.py -v
The tmux integration uses a private socket and substitutes only pane payloads.
"""
import os
from pathlib import Path
import pty
import select
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest


if Path(sys.argv[0]).name == 'tmux':
    args = sys.argv[1:]
    if args and args[0] in ('new-session', 'split-window'):
        args[-1] = 'sleep 120 # ORIGINAL=' + args[-1].replace('\n', ' ')
    raise SystemExit(subprocess.call([os.environ['SPL_TEST_REAL_TMUX'], '-S',
                                    os.environ['SPL_TEST_SOCKET']] + args))


# Optional exact baseline source tree supports repeatable RED verification.
ROOT = Path(os.environ.get('SPL_TEST_SOURCE_ROOT', Path(__file__).resolve().parents[1]))
AUDIT = ROOT / 'scripts/fedora/console_audit.bash'
BROKER = ROOT / 'scripts/fedora/session_pane.sh'


class FedoraSessions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='spl-fedora-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ)
        for key in ('BASH_ENV', 'ENV', 'TMUX', 'SPL_CONSOLE_AUDIT_LOADED'):
            self.env.pop(key, None)
        self.env.update(HISTFILE='/dev/null', TMPDIR=str(self.root),
                        SPL_STATE_ROOT=str(self.root / 'state'),
                        SPL_TMUX_SESSION_NAME='spl-isolated-regression')

    def bash(self, command, *, interactive=True, env=None):
        args = ['/usr/bin/bash', '--noprofile', '--norc',
                '-ic' if interactive else '-c', command, 'fixture', str(AUDIT), str(BROKER)]
        result = subprocess.run(args, env=env or self.env, text=True,
                                capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_three_scripts_have_valid_bash_syntax(self):
        for path in (AUDIT, BROKER, ROOT / 'scripts/fedora/install_session_panes.sh'):
            result = subprocess.run(['/usr/bin/bash', '-n', str(path)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_selftest_round_trip(self):
        out = self.bash('"$2" self-test', interactive=False)
        self.assertIn('SELFTEST-OK', out)

    def test_noninteractive_source_does_not_set_loaded_flag(self):
        out = self.bash('source "$1"; printf "FLAG=%s" "${SPL_CONSOLE_AUDIT_LOADED-unset}"',
                        interactive=False)
        self.assertEqual(out, 'FLAG=unset')

    def test_child_initializes_despite_inherited_loaded_flag(self):
        env = dict(self.env, SPL_CONSOLE_AUDIT_LOADED='1')
        out = self.bash('source "$1"; declare -F __spl_audit_prompt_marker; '
                        'export -p | /usr/bin/grep SPL_CONSOLE_AUDIT_LOADED || true', env=env)
        self.assertIn('__spl_audit_prompt_marker', out)
        self.assertNotIn('declare -x SPL_CONSOLE_AUDIT_LOADED', out)

    def test_actual_nested_interactive_child_initializes(self):
        out = self.bash('source "$1"; /usr/bin/bash --noprofile --norc -ic '
                        '\'source "$1"; declare -F __spl_audit_prompt_marker\' child "$1"')
        self.assertIn('__spl_audit_prompt_marker', out)

    def test_same_shell_source_is_idempotent(self):
        out = self.bash('source "$1"; before=$(declare -p PROMPT_COMMAND PS1); '
                        'trap_before=$(trap -p DEBUG); source "$1"; '
                        '[[ "$before" == "$(declare -p PROMPT_COMMAND PS1)" ]] || exit 71; '
                        '[[ "$trap_before" == "$(trap -p DEBUG)" ]] || exit 72; printf IDEMPOTENT')
        self.assertIn('IDEMPOTENT', out)

    def test_prompt_array_runs_all_hooks_and_preserves_exit_status(self):
        out = self.bash('PROMPT_COMMAND=("printf FIRST" "printf SECOND"); source "$1"; '
                        '(exit 17); __spl_audit_prompt_marker; result=$?; '
                        'printf "\nSTATUS=%s\n" "$result"')
        self.assertIn('FIRSTSECOND', out)
        self.assertEqual(out.count('FIRST'), 1)
        self.assertEqual(out.count('SECOND'), 1)
        self.assertIn('STATUS=17', out)

    def test_scalar_prompt_hook_runs_once_and_preserves_exit_status(self):
        out = self.bash('PROMPT_COMMAND="printf SCALAR"; source "$1"; source "$1"; '
                        '(exit 23); __spl_audit_prompt_marker; result=$?; '
                        'printf "\nSTATUS=%s\n" "$result"')
        self.assertEqual(out.count('SCALAR'), 1)
        self.assertIn('STATUS=23', out)

    def test_prompt_hooks_observe_original_status_then_previous_hook_status(self):
        out = self.bash('PROMPT_COMMAND=(\'seen=$?; (exit 5)\' \'second=$?\'); '
                        'source "$1"; (exit 17); eval "$PROMPT_COMMAND"; result=$?; '
                        'printf "OBSERVED=%s,%s RETURN=%s" "$seen" "$second" "$result"')
        self.assertIn('OBSERVED=17,5 RETURN=17', out)

    def test_existing_debug_trap_is_preserved(self):
        out = self.bash('trap ":" DEBUG; before=$(trap -p DEBUG); source "$1"; '
                        'eval "$PROMPT_COMMAND"; '
                        '[[ "$before" == "$(trap -p DEBUG)" ]] || exit 73; printf TRAP_PRESERVED')
        self.assertIn('TRAP_PRESERVED', out)

    def test_first_prompt_installs_debug_hook_only_once(self):
        out = self.bash('source "$1"; eval "$PROMPT_COMMAND"; '
                        'first=$(trap -p DEBUG); [[ $first == *"__spl_audit_preexec"* ]] || exit 74; '
                        'eval "$PROMPT_COMMAND"; [[ "$first" == "$(trap -p DEBUG)" ]] || exit 75; '
                        'printf DEBUG_INSTALLED')
        self.assertIn('DEBUG_INSTALLED', out)

    def test_repeated_prompt_has_no_internal_result_markers(self):
        # The second explicit eval is a user command and earns one marker;
        # its prompt bookkeeping must not produce additional phantom markers.
        out = self.bash('source "$1"; eval "$PROMPT_COMMAND"; eval "$PROMPT_COMMAND"')
        self.assertEqual(out.count(' RESULT'), 1, out)

    def test_real_interactive_prompt_preserves_debug_and_hook_status(self):
        rcfile = self.root / 'interactive-rc.bash'
        rcfile.write_text('trap ":" DEBUG\n'
                          'before=$(trap -p DEBUG)\n'
                          'PROMPT_COMMAND=(\'seen=$?; (exit 5)\' \'second=$?\')\n'
                          'PS1="__SPL_PROMPT_SENTINEL__ "\n'
                          'source "' + str(AUDIT) + '"\n'
                          '[[ "$before" == "$(trap -p DEBUG)" ]] || exit 81\n')
        pid, fd = pty.fork()
        if pid == 0:
            os.execve('/usr/bin/bash', ['/usr/bin/bash', '--noprofile', '--rcfile',
                                      str(rcfile), '-i'], self.env)
        chunks = bytearray()
        reaped = False
        try:
            def read_prompt():
                current = bytearray()
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if select.select([fd], [], [], 0.1)[0]:
                        try:
                            block = os.read(fd, 65536)
                        except OSError:
                            self.fail('Shell exited before prompt; source may have replaced DEBUG: '
                                      + chunks.decode(errors='replace'))
                        current.extend(block)
                        chunks.extend(block)
                        if b'__SPL_PROMPT_SENTINEL__ ' in current:
                            return
                self.fail('Real interactive prompt missing: ' + chunks.decode(errors='replace'))
            read_prompt()
            os.write(fd, b'(exit 17)\n')
            read_prompt()
            os.write(fd, b'printf "REAL_PROBE=<%s,%s> TRAP=<%s>\\n" "$seen" "$second" "$(trap -p DEBUG)"; exit\n')
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if select.select([fd], [], [], 0.1)[0]:
                    try:
                        block = os.read(fd, 65536)
                    except OSError:
                        break
                    chunks.extend(block)
                done, status = os.waitpid(pid, os.WNOHANG)
                if done:
                    reaped = True
                    self.assertEqual(os.waitstatus_to_exitcode(status), 0)
                    break
            output = chunks.decode(errors='replace')
            self.assertIn("REAL_PROBE=<17,5> TRAP=<trap -- ':' DEBUG>", output)
        finally:
            os.close(fd)
            if not reaped:
                done, status = os.waitpid(pid, os.WNOHANG)
                if not done:
                    os.kill(pid, 15)
                    os.waitpid(pid, 0)

    def test_new_state_directories_are_private_under_permissive_caller_umask(self):
        self.bash('umask 022; "$2" inspect claude', interactive=False)
        for path in ('state', 'state/restart', 'state/requests'):
            self.assertEqual(stat.S_IMODE((self.root / path).stat().st_mode), 0o700, path)

    def test_existing_state_directory_mode_is_not_changed(self):
        state = self.root / 'state'
        state.mkdir(mode=0o755)
        state.chmod(0o755)
        self.bash('"$2" inspect claude', interactive=False)
        self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o755)

    @unittest.skipUnless(shutil.which('tmux'), 'tmux unavailable')
    def test_layout_focus_and_repeated_prepare(self):
        real_tmux = shutil.which('tmux')
        socket = str(self.root / 'tmux.sock')
        bindir = self.root / 'bin'
        bindir.mkdir()
        (bindir / 'tmux').symlink_to(Path(__file__).resolve())
        env = dict(self.env, PATH=str(bindir) + ':' + self.env.get('PATH', ''),
                   SPL_TEST_REAL_TMUX=real_tmux, SPL_TEST_SOCKET=socket)
        def query(*args):
            result = subprocess.run([real_tmux, '-S', socket] + list(args),
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout
        self.addCleanup(lambda: subprocess.run([real_tmux, '-S', socket, 'kill-server'],
                                               capture_output=True, timeout=10))
        self.bash('source "$2" prepare; select_agent_pane codex', interactive=False, env=env)
        target = 'spl-isolated-regression:0'
        rows = query('list-panes', '-t', target, '-F', '#{pane_index} #{pane_start_command}').splitlines()
        self.assertEqual(len(rows), 4)
        self.assertIn('host claude', rows[0])
        self.assertIn('host codex', rows[1])
        self.assertIn('--rcfile', rows[2])
        self.assertIn('--rcfile', rows[3])
        self.assertEqual(query('display-message', '-p', '-t', target, '#{pane_index}').strip(), '1')
        ids = query('list-panes', '-t', target, '-F', '#{pane_id}')
        self.bash('"$2" prepare', interactive=False, env=env)
        self.assertEqual(query('list-panes', '-t', target, '-F', '#{pane_id}'), ids)


if __name__ == '__main__':
    unittest.main()
