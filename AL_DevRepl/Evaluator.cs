using System.Collections;
using System.Globalization;
using System.Reflection;

namespace AL_DevRepl;

internal sealed class Evaluator(Assembly compiler)
{
    private readonly StringWriter output = new(CultureInfo.InvariantCulture);
    private readonly HashSet<string> references = new(StringComparer.OrdinalIgnoreCase);
    private object? evaluator;
    private object printer = null!;
    private MethodInfo evaluate = null!;
    private MethodInfo reference = null!;
    private PropertyInfo errors = null!;

    public Reply Run(string code)
    {
        if (code.Trim() == ":reset")
        {
            evaluator = null;
            return new Reply(true, "Compiler state cleared.");
        }

        output.GetStringBuilder().Clear();
        ReplScope.Output = output;
        try
        {
            if (evaluator is null)
                Initialize();
            else
                ReferenceLoadedAssemblies();
            if (code.TrimStart().StartsWith('='))
                code = "Print(\n" + code.TrimStart()[1..] + "\n);";
            object?[] arguments = { code, null, false };
            var remaining = evaluate.Invoke(evaluator, arguments);
            if ((int)errors.GetValue(printer)! != 0)
                return new Reply(false, output.ToString());
            if (remaining is not null)
                return new Reply(false, output + "Incomplete C# submission.");
            return new Reply(true, output + ((bool)arguments[2]! ? Format(arguments[1]) : ""));
        }
        catch (Exception error)
        {
            return new Reply(false, output + (error.InnerException ?? error).ToString());
        }
        finally
        {
            ReplScope.Output = null;
        }
    }

    private void Initialize()
    {
        Type GetType(string name) => compiler.GetType("Mono.CSharp." + name, throwOnError: true)!;
        var settingsType = GetType("CompilerSettings");
        var settings = Activator.CreateInstance(settingsType);
        settingsType.GetField("Version")!.SetValue(settings, Enum.Parse(GetType("LanguageVersion"), "Experimental"));
        settingsType.GetField("GenerateDebugInfo")!.SetValue(settings, false);
        settingsType.GetField("WarningLevel")!.SetValue(settings, 0);
        printer = Activator.CreateInstance(GetType("StreamReportPrinter"), output)!;
        errors = printer.GetType().GetProperty("ErrorsCount")!;
        var context = Activator.CreateInstance(GetType("CompilerContext"), settings, printer);
        var evaluatorType = GetType("Evaluator");
        evaluator = Activator.CreateInstance(evaluatorType, context);
        evaluatorType.GetProperty("InteractiveBaseClass")!.SetValue(evaluator, typeof(ReplScope));
        evaluate = evaluatorType.GetMethod("Evaluate", new[]
            { typeof(string), typeof(object).MakeByRefType(), typeof(bool).MakeByRefType() })!;
        reference = evaluatorType.GetMethod("ReferenceAssembly", new[] { typeof(Assembly) })!;

        references.Clear();
        references.UnionWith(new[] { "mscorlib", "System", "System.Core", "System.Xml" });
        ReferenceLoadedAssemblies();
        evaluate.Invoke(evaluator, new object?[] { "using System; using System.Linq; using System.Collections.Generic;" +
            " using UnityEngine; using UnityEngine.SceneManagement;", null, false });
        if ((int)errors.GetValue(printer)! != 0)
        {
            evaluator = null;
            throw new InvalidOperationException("Could not set up default imports.");
        }
    }

    private void ReferenceLoadedAssemblies()
    {
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            if (assembly.IsDynamic || !references.Add(assembly.GetName().Name!))
                continue;
            try { reference.Invoke(evaluator, new object[] { assembly }); }
            catch (TargetInvocationException error) when (error.InnerException is FileNotFoundException or FileLoadException or TypeLoadException) { }
        }
    }

    internal static string Format(object? value)
    {
        if (value is string || value is not IEnumerable sequence) return value?.ToString() ?? "null";
        return string.Join(Environment.NewLine, sequence.Cast<object?>().Take(100).Select(item => item?.ToString() ?? "null"));
    }
}

public class ReplScope
{
    internal static TextWriter? Output;
    public static void Print(object? value) => Output?.WriteLine(Evaluator.Format(value));
}
