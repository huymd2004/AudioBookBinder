//
//  Copyright (c) 2009, Oleksandr Tymoshenko <gonzo@bluezbox.com>
//  All rights reserved.
// 
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions
//  are met:
//  1. Redistributions of source code must retain the above copyright
//     notice unmodified, this list of conditions, and the following
//     disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright
//     notice, this list of conditions and the following disclaimer in the
//     documentation and/or other materials provided with the distribution.
// 
//  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
//  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
//  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
//  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
//  OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
//  SUCH DAMAGE.
//

#import <Foundation/Foundation.h>
#import <Foundation/NSDebug.h> 
#import <QTKit/QTKit.h>
#include <getopt.h>

#import "AudioBinder.h"
#import "ABLog.h"
#import "ConsoleDelegate.h"
#import "MP4File.h"

#define NUM_VALID_RATES 9
int validRates[NUM_VALID_RATES] = { 8000, 11025, 12000, 16000, 22050,
    24000, 32000, 44100, 48000};

void usage(char *cmd)
{
    printf("Usage: %s [-hsv] [-c 1|2] [-r samplerate] [-a author] [-t title] [-i filelist] outfile [infile ...]\n", cmd);
    printf("\t-a author\tset book author\n");
    printf("\t-c 1|2\t\tnumber of channels in audiobook. Default: 2\n");
    printf("\t-C file.png\t\tcover image\n");
    printf("\t-h\t\tshow this message\n");
    printf("\t-i file\t\tget input files list from file, \"-\" for standard input\n");
    printf("\t-r rate\t\tsample rate of audiobook. Default: 44100\n");
    printf("\t-s\t\tskip errors and go on with conversion\n");
    printf("\t-t title\tset book title\n");
    printf("\t-v\t\tprint some info on files being converted\n");
    
}

int main (int argc, char * argv[]) {
    int c, i;
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    AudioBinder *binder = [[AudioBinder alloc] init];
    NSString *bookAuthor = nil;
    NSString *bookTitle = nil;
    NSString *outFile = nil;
    NSString *inputFileList = nil;
    NSString *coverFile = nil;
    NSMutableArray *inputFiles;
    NSError *error;
    ConsoleDelegate *delegate;
    BOOL verbose = NO;
    BOOL skipErrors = NO;
    int channels = 2;
    float samplerate = 44100.;
    
    NSZombieEnabled = YES;
    while ((c = getopt(argc, argv, "a:c:C:hi:r:st:v")) != -1) {
        switch (c) {
            case 'h':
                usage(argv[0]);
                exit(0);
            case 'a':
                bookAuthor = [NSString stringWithUTF8String:optarg];
                break;
            case 't':
                bookTitle = [NSString stringWithUTF8String:optarg];
                break;
            case 'i':
                inputFileList = [NSString stringWithUTF8String:optarg];
                break;
            case 'v':
                verbose = YES;
                break;
            case 's':
                skipErrors = YES;
                break;
            case 'c':
                channels = atoi(optarg);
                break;
            case 'r':
                samplerate = atof(optarg);
                break;
            case 'C':
                coverFile = [NSString stringWithUTF8String:optarg];
                break;
            default:
                usage(argv[0]);
                exit(1);
        }
    }
    
    // Do we have output file et al?
    if (optind < argc) 
    {
            outFile = [NSString stringWithUTF8String:argv[optind]];
            optind++;
    }
    else
    {
        fprintf(stderr, "No output file specified\n");
        usage(argv[0]);
        exit(1);
    }

    if (channels != 1 && channels != 2) {
        fprintf(stderr, "only 1 and 2 are valid as -c argument");
        exit(1);
    }
    
    for (i = 0; i < NUM_VALID_RATES; i++) {
        if (validRates[i] == samplerate)
            break;
    }
    
    if (i == NUM_VALID_RATES) {
        fprintf(stderr, "Invalid sample rate. Valid rates: ");
        for (i = 0; i < NUM_VALID_RATES; i++) {
            if (i)
                fprintf(stderr, ", ");
            fprintf(stderr, "%d", validRates[i]);
        }
        fprintf(stderr, "\n");
        exit(1);
    }

    // Get input files from all possible sources:
    // 
    inputFiles = [[NSMutableArray alloc] init];
    if (inputFileList != nil)
    {
        // Add files from the list file
        NSString *listContent;
        if ([inputFileList isEqualToString:@"-"])
        {
            NSData *data = 
                [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
            listContent = [[NSString alloc] initWithData:data 
                                                encoding:NSUTF8StringEncoding]; 

        }
        else
            listContent = [[NSString alloc] 
                       initWithContentsOfFile:inputFileList
                                     encoding:NSUTF8StringEncoding
                                        error:&error];
        
        if (listContent == nil) {
            ABLog(@"Error reading file at %@\n%@", 
                  inputFileList, [error localizedFailureReason]);
            usage(argv[0]);
            exit(1);
        }

        NSArray *filesList = [listContent componentsSeparatedByString: @"\n"];
        for (NSString *file in filesList)
            if ([file length] > 0)
                [inputFiles addObject:file];
    }

    // Now get input files from the remain of arguments
    while (optind < argc) 
    {
        [inputFiles addObject:[NSString stringWithUTF8String:argv[optind]]];
        optind++;
    }

    if ([inputFiles count] == 0)
    {
        fprintf(stderr, "No input file specified\n");
        usage(argv[0]);
        exit(1);
    }

    // Feed files to binder
    [binder setOutputFile:outFile];
    for (NSString *file in inputFiles) 
        [binder addInputFile:file];
    
    binder.channels = channels;
    binder.sampleRate = samplerate;

    // Setup delegate, it will print progress messages on console
    delegate = [[ConsoleDelegate alloc] init];
    [delegate setVerbose:verbose];
    [delegate setSkipErrors:skipErrors];
    [binder setDelegate:delegate];   

    if (![binder convert])
    {
        ABLog(@"Conversion failed");
        exit(255);
    }
    
    if ((bookAuthor != nil) || (bookTitle != nil) || (coverFile != nil))
    {
        printf("Adding metadata, it may take a while...");
        fflush(stdout);
        MP4File *mp4 = [[MP4File alloc] initWithFileName:outFile];
        [mp4 setArtist:bookAuthor]; 
        [mp4 setTitle:bookTitle]; 
        [mp4 setCoverFile:coverFile];
        [mp4 updateFile];
        printf("done\n");
    }

    [pool drain];
    return 0;
}
