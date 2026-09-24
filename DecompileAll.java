import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import java.io.PrintWriter;

/** Decompile every function in the program to one greppable file. */
public class DecompileAll extends GhidraScript {
    @Override
    public void run() throws Exception {
        String out = getScriptArgs().length > 0 ? getScriptArgs()[0] : "/work/decomp.c";
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        int ok = 0, fail = 0;
        try (PrintWriter w = new PrintWriter(out)) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                if (monitor.isCancelled()) break;
                DecompileResults r = d.decompileFunction(f, 90, monitor);
                w.println("/* ==== " + f.getName() + " @ " + f.getEntryPoint() + " ==== */");
                if (r.decompileCompleted()) { w.println(r.getDecompiledFunction().getC()); ok++; }
                else { w.println("/* decompile failed: " + r.getErrorMessage() + " */"); fail++; }
            }
        }
        d.dispose();
        println("DECOMPILED ok=" + ok + " failed=" + fail + " -> " + out);
    }
}
