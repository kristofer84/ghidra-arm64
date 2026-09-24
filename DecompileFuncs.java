import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;

public class DecompileFuncs extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] names = getScriptArgs();
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        for (String n : names) {
            boolean found = false;
            // Accept a raw address too: the interesting functions are often
            // static, so they have no symbol to match on.
            if (n.startsWith("0x")) {
                ghidra.program.model.address.Address a = toAddr(Long.parseLong(n.substring(2), 16));
                Function f = getFunctionContaining(a);
                // A handler reached only through a dispatch table has no call
                // referencing it, so auto-analysis never makes it a function and
                // getFunctionContaining returns null. Create one at the address.
                if (f == null) f = createFunction(a, null);
                if (f != null) {
                    DecompileResults r = d.decompileFunction(f, 180, monitor);
                    println("@@@BEGIN " + n + " -> " + f.getName() + " @ " + f.getEntryPoint());
                    println(r.decompileCompleted() ? r.getDecompiledFunction().getC()
                                                   : "DECOMPILE FAILED: " + r.getErrorMessage());
                    println("@@@END " + n);
                } else println("@@@MISSING " + n);
                continue;
            }
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                if (!f.getName().equals(n)) continue;
                found = true;
                DecompileResults r = d.decompileFunction(f, 180, monitor);
                println("@@@BEGIN " + n + " @ " + f.getEntryPoint());
                println(r.decompileCompleted() ? r.getDecompiledFunction().getC()
                                               : "DECOMPILE FAILED: " + r.getErrorMessage());
                println("@@@END " + n);
            }
            if (!found) println("@@@MISSING " + n);
        }
        d.dispose();
    }
}
