from mojopack.cli import CLI
from mojopack.container import ContainerUtils
from std.os.path import exists, isfile
from std.io.file import open

def main() raises:
    print("=== Running Archive End-to-End Tests ===")
    
    # Create sample files
    var sample_dir = String("/tmp/mpack_e2e")
    var f1 = sample_dir + "/test1.txt"
    var f2 = sample_dir + "/test2.txt"
    
    ContainerUtils.ensure_dir(sample_dir)
        
    with open(f1, "w") as f:
        f.write("Hello MojoPack solid archive file 1!\n" * 20)
        
    with open(f2, "w") as f:
        f.write("Hello MojoPack solid archive file 2!\n" * 20)
        
    var arch = String("/tmp/e2e_archive.mpk")
    var input_paths = List[String]()
    input_paths.append(sample_dir)
    
    # Create
    CLI.create(arch, input_paths, 1)
    if not exists(arch):
        raise Error("Failed to create archive: " + arch)
    print("[PASS] Archive created successfully")
    
    # List
    CLI.list_contents(arch)
    print("[PASS] Archive listed successfully")
    
    # Test
    CLI.test_integrity(arch)
    print("[PASS] Archive integrity verified")
    
    # Extract
    var out_dir = String("/tmp/e2e_extracted")
    CLI.extract(arch, out_dir)
    print("[PASS] Archive extracted successfully")
    
    print("ALL ARCHIVE END-TO-END TESTS PASSED!\n")
