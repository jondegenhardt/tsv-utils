/**
A simple version of the unix 'cat' program. It is used for performance testing,
*/
module tsv_utils.dcat;

import std.stdio;
import std.typecons : Flag, No, Yes, tuple;

auto helpText = q"EOS
Synopsis: dcat [options] [file]

dcat reads from a file or standard input and writes each line to standard
output. This program is used for performance testing.

Options:
EOS";

enum DCatTestType { byLine, chunkByLine, chunkByChunk, chunkByChunkDirect, bufferedByLine,
                    bufferedByChar, altBufferedByChar, bufferedByCharDirect, bufferedByLineByChar };

/** Container for command line options.
 */
struct DCatOptions
{
    enum defaultHeaderString = "line";

    string programName;
    DCatTestType dcatTest;


    /* Returns a tuple. First value is true if command line arguments were successfully
     * processed and execution should continue, or false if an error occurred or the user
     * asked for help. If false, the second value is the appropriate exit code (0 or 1).
     */
    auto processArgs (ref string[] cmdArgs)
    {
        import std.algorithm : any, each;
        import std.getopt;
        import std.path : baseName, stripExtension;

        programName = (cmdArgs.length > 0) ? cmdArgs[0].stripExtension.baseName : "Unknown_program_name";

        try
        {
            auto r = getopt(
                cmdArgs,
                std.getopt.config.caseSensitive,
                "t|test", "byLine, chunkByLine, chunkByChunk, chunkByChunkDirect, bufferedByLine", &dcatTest,
            );

            if (r.helpWanted)
            {
                defaultGetoptPrinter(helpText, r.options);
                return tuple(false, 0);
            }

        }
        catch (Exception exc)
        {
            stderr.writefln("[%s] Error processing command line arguments: %s", programName, exc.msg);
            return tuple(false, 1);
        }
        return tuple(true, 0);
    }
}

/** Main program. */
int main(string[] cmdArgs)
{
    /* When running in DMD code coverage mode, turn on report merging. */
    version(D_Coverage) version(DigitalMars)
    {
        import core.runtime : dmd_coverSetMerge;
        dmd_coverSetMerge(true);
    }

    DCatOptions cmdopt;
    auto r = cmdopt.processArgs(cmdArgs);
    if (!r[0]) return r[1];
    try dcat(cmdopt, cmdArgs[1..$]);
    catch (Exception exc)
    {
        stderr.writefln("Error [%s]: %s", cmdopt.programName, exc.msg);
        return 1;
    }

    return 0;
}

/** Implements the primary logic behind dcat.
 *
 * Reads lines from each file, outputing each line number to standard output.
 */
void dcat(in DCatOptions cmdopt, in string[] inputFiles)
{
    import std.conv : to;
    import std.range;
    import tsv_utils.common.utils : BufferedOutputRange;

    auto bufferedOutput = BufferedOutputRange!(typeof(stdout))(stdout);
    auto filename = inputFiles.length > 0 ? inputFiles[0] : "-";

    final switch(cmdopt.dcatTest)
    {
    case DCatTestType.byLine:
        testByLine(cmdopt, filename, bufferedOutput);
        break;

    case DCatTestType.chunkByLine:
        testChunkByLine(cmdopt, filename, bufferedOutput);
        break;

    case DCatTestType.chunkByChunk:
        testChunkByChunk(cmdopt, filename, bufferedOutput);
        break;

    case DCatTestType.chunkByChunkDirect:
        testChunkByChunkDirect(cmdopt, filename);
        break;

    case DCatTestType.bufferedByLine:
        testBufferedByLine(cmdopt, filename, bufferedOutput);
        break;

    case DCatTestType.bufferedByChar:
        testBufferedByChar(cmdopt, filename, bufferedOutput);
        break;

    case DCatTestType.altBufferedByChar:
        testAltBufferedByChar(cmdopt, filename, bufferedOutput);
        break;

    case DCatTestType.bufferedByCharDirect:
        testBufferedByCharDirect(cmdopt, filename);
        break;

    case DCatTestType.bufferedByLineByChar:
        testBufferedByLineByChar(cmdopt, filename, bufferedOutput);
        break;

    }
}

void testByLine(OutputRange)(DCatOptions cmdopt, string filename, auto ref OutputRange outputStream)
{
    import std.range;

    auto inputStream = (filename == "-") ? stdin : filename.File();
    foreach (line; inputStream.byLine(KeepTerminator.no))
    {
        outputStream.put(line);
        outputStream.put('\n');
    }
}

void testChunkByLine(OutputRange)(DCatOptions cmdopt, string filename, auto ref OutputRange outputStream)
{
    import std.algorithm : splitter;

    ubyte[1024 * 128] fileRawBuf;
    auto ifile = (filename == "-") ? stdin : filename.File;

    foreach (ref ubyte[] buffer; ifile.byChunk(fileRawBuf))
    {
        bool first = true;
        foreach (ref line; buffer.splitter('\n'))
        {
            if (first) first = false;
            else outputStream.put('\n');
            outputStream.put(line);
        }
    }
}

void testChunkByChunk(BufferedOutputRange)(DCatOptions cmdopt, string filename, auto ref BufferedOutputRange outputStream)
{
    import std.algorithm : splitter;

    ubyte[1024 * 128] fileRawBuf;
    auto ifile = (filename == "-") ? stdin : filename.File;

    foreach (ref ubyte[] buffer; ifile.byChunk(fileRawBuf))
    {
        outputStream.append(buffer);
        outputStream.flushIfFull;
    }
    outputStream.flush;
}

void testChunkByChunkDirect(DCatOptions cmdopt, string filename)
{
    import std.algorithm : copy, splitter;

    auto ifile = (filename == "-") ? stdin : filename.File;
    foreach (ref c; ifile.byChunk(1024 * 128)) stdout.rawWrite(c);
}

void testBufferedByLine(OutputRange)(DCatOptions cmdopt, string filename, auto ref OutputRange outputStream)
{
    import std.range;
    import tsv_utils.common.utils : bufferedByLine;

    auto inputStream = (filename == "-") ? stdin : filename.File();
    foreach (ref line; inputStream.bufferedByLine!(Yes.keepTerminator))
    {
        outputStream.put(line);
    }
}

void testBufferedByLineByChar(OutputRange)(DCatOptions cmdopt, string filename, auto ref OutputRange outputStream)
{
    import std.range;
    import tsv_utils.common.utils : bufferedByLine;

    auto inputStream = (filename == "-") ? stdin : filename.File();
    foreach (ref line; inputStream.bufferedByLine!(Yes.keepTerminator))
    {
        foreach (c; line) outputStream.put(c);
    }
}

void testBufferedByChar(OutputRange)(DCatOptions cmdopt, string filename, auto ref OutputRange outputStream)
{
    import std.range;

    auto inputStream = (filename == "-") ? stdin : filename.File();

    foreach (c; inputStream.bufferedByChar!char) outputStream.put(c);
}

void testBufferedByCharDirect(DCatOptions cmdopt, string filename)
{
    import std.range;
    import tsv_utils.common.utils : bufferedByLine;

    auto inputStream = (filename == "-") ? stdin : filename.File();

    ubyte[1] x;
    foreach (c; inputStream.bufferedByChar!ubyte) { x[0] = c; stdout.rawWrite(x); }
}

void testAltBufferedByChar(OutputRange)(DCatOptions cmdopt, string filename, auto ref OutputRange outputStream)
{
    import std.range;

    ubyte[1024 * 128] buffer;

    auto inputStream = (filename == "-") ? stdin : filename.File();

    while (!inputStream.eof)
    {
        foreach (c; inputStream.rawRead(buffer)) outputStream.put(cast(char) c);
    }
}

auto bufferedByChar(Char = char, size_t readSize = 1024 * 128)(File file)
if (is(Char == char) || is(Char == ubyte))
{
    import std.range;

    static assert(0 < readSize);

    static final class BufferedByCharImpl
    {
        private File _file;
        private ubyte[readSize] _rawBuffer;
        private ubyte[] _buffer;

        this (File f)
        {
            _file = f;
            _buffer = _file.rawRead(_rawBuffer);
        }

        bool empty() const
        {
            return _buffer.empty && _file.eof;
        }

        Char front()
        {
            assert(!empty, "Attempt to take the front of an empty bufferdByChar.");

            return cast(Char) _buffer.front;
        }

        void popFront()
        {
            assert(!empty, "Attempt to popFront an empty bufferedByChar.");

            _buffer.popFront;

            if (_buffer.empty) _buffer = _file.rawRead(_rawBuffer);
        }
    }

    assert(file.isOpen, "bufferedByChar passed a closed file.");

    return new BufferedByCharImpl(file);
}
