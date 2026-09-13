from std.sys import argv
from mojopack.cli import CLI

def main() raises:
    var args = argv()
    if len(args) < 2:
        CLI.print_usage()
        return

    var cmd = args[1]
    if cmd == "c" or cmd == "create":
        var level = 1
        var start_idx = 2
        if len(args) > start_idx and (args[start_idx] == "-1" or args[start_idx] == "--fast"):
            level = 1
            start_idx += 1
        elif len(args) > start_idx and (args[start_idx] == "-9" or args[start_idx] == "--ultra"):
            level = 9
            start_idx += 1

        if len(args) < start_idx + 2:
            print("Error: Missing archive name or input path(s).")
            CLI.print_usage()
            return

        var arch_path = args[start_idx]
        var input_paths = List[String]()
        for i in range(start_idx + 1, len(args)):
            input_paths.append(args[i])

        CLI.create(arch_path, input_paths, level)

    elif cmd == "x" or cmd == "extract":
        if len(args) < 3:
            print("Error: Missing archive name.")
            CLI.print_usage()
            return
        var arch_path = args[2]
        var dest_dir = String(".")
        if len(args) >= 5 and (args[3] == "-o" or args[3] == "--output"):
            dest_dir = args[4]
        elif len(args) >= 4 and not args[3].startswith("-"):
            dest_dir = args[3]
        CLI.extract(arch_path, dest_dir)

    elif cmd == "l" or cmd == "list":
        if len(args) < 3:
            print("Error: Missing archive name.")
            CLI.print_usage()
            return
        CLI.list_contents(args[2])

    elif cmd == "t" or cmd == "test":
        if len(args) < 3:
            print("Error: Missing archive name.")
            CLI.print_usage()
            return
        CLI.test_integrity(args[2])

    elif cmd == "b" or cmd == "benchmark":
        if len(args) < 3:
            print("Error: Missing target path to benchmark.")
            CLI.print_usage()
            return
        CLI.benchmark(args[2])

    elif cmd == "-v" or cmd == "--version" or cmd == "version":
        CLI.print_version()

    elif cmd == "-h" or cmd == "--help" or cmd == "help":
        CLI.print_usage()

    else:
        print("Unknown command: " + cmd)
        CLI.print_usage()
