#import <LocalAuthentication/LocalAuthentication.h>
#import "teaBASE.h"

BOOL run(NSString *cmd, NSArray *args, NSPipe *pipe) {
    NSTask *task = [NSTask new];
    [task setLaunchPath:cmd];
    [task setArguments:args];
    if (pipe) [task setStandardError:pipe];
    id error;
    [task launchAndReturnError:&error]; // configures task to not throw and thus potentially break us
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

@implementation teaBASE

- (void)mainViewDidLoad {
    for (NSTableColumn *col in self.gitExtensionsTable.tableColumns) {
        col.headerCell.attributedStringValue = [[NSAttributedString alloc] initWithString:col.title attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:10]}];
    }
}

- (void)willSelect {
    BOOL hasSSH = [self checkForSSH];
    BOOL hasSSHPassPhrase = hasSSH && [self checkForSSHPassPhrase]; // check both ∵ our pp-check is false-positive if no key file
    BOOL hasSignedCommits = [self gpgSignEnabled];
    [self.sshSwitch setState:hasSSH ? NSControlStateValueOn : NSControlStateValueOff];
    [self.sshPassPhraseSwitch setState:hasSSHPassPhrase ? NSControlStateValueOn : NSControlStateValueOff];
    [self.gpgSignSwitch setState:hasSignedCommits ? NSControlStateValueOn : NSControlStateValueOff];
    [self.homebrewSwitch setState:[self homebrewInstalled] ? NSControlStateValueOn : NSControlStateValueOff];
    [self.pkgxSwitch setState:[self pkgxInstalled] ? NSControlStateValueOn : NSControlStateValueOff];
    
    if (hasSSH) {
        // being able to turn this off is a bit weird, maybe we'll support it later
        [self.sshSwitch setEnabled:NO];
        //TODO actually it's easy to just delete them, needs a confirm first tho
        [self.sshSwitch setToolTip:@"Delete `~/.ssh/id_rsa*` to disable. You shouldn’t do this though."];
    }
    if (hasSSHPassPhrase) {
        [self.sshPassPhraseSwitch setEnabled:NO];
        //TODO actually it’s not too bad to undo
        [self.sshPassPhraseSwitch setToolTip:@"Undoing a passphrase is not trivial and not recommended."];
    }
    
    [self calculateSecurityRating];
}

- (void)calculateSecurityRating {
    BOOL hasSignedCommits = self.gpgSignSwitch.state == NSControlStateValueOn;
    BOOL hasSSHPassPhrase = self.sshPassPhraseSwitch.state == NSControlStateValueOn;
    BOOL hasSSH = self.sshSwitch.state == NSControlStateValueOn;
    
    float rating = (hasSignedCommits ? 1 : 0) + (hasSSHPassPhrase ? 1 : 0) + (hasSSH ? 1 : 0);
    [self.ratingIndicator setIntValue:rating];
    
    if (self.ratingIndicator.intValue >= self.ratingIndicator.maxValue) {
        [self.ratingIndicator setFillColor:[NSColor systemGreenColor]];
    } else if (self.ratingIndicator.intValue <= 1) {
        [self.ratingIndicator setFillColor:[NSColor systemRedColor]];
    }
}

- (BOOL)checkForSSH {
    NSURL *home = [NSFileManager.defaultManager homeDirectoryForCurrentUser];
    NSString *id_rsa = [home.path stringByAppendingPathComponent: @".ssh/id_rsa"];
    return [NSFileManager.defaultManager isReadableFileAtPath:id_rsa];
}

- (BOOL)checkForSSHPassPhrase {
    id path = [NSString stringWithFormat:@"%@/.ssh/id_rsa", NSFileManager.defaultManager.homeDirectoryForCurrentUser.path];
    
    // attempts to decrypt the key, if there’s a passphrase this will fail
    return run(@"/usr/bin/ssh-keygen", @[@"-y", @"-f", path, @"-P", @""], nil) == NO;
}

- (BOOL)gpgSignEnabled {
    NSURL *home = [NSFileManager.defaultManager homeDirectoryForCurrentUser];
    NSString *id_rsa = [home.path stringByAppendingPathComponent: @".gitconfig"];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:id_rsa];
    
    if (fileHandle == nil) {
        return NO; // TODO error condition
    }
    
    // Read the first 1024 bytes (or less if the file is shorter)
    NSData *fileData = [fileHandle readDataOfLength:1024];
    [fileHandle closeFile];
    
    if (fileData == nil || [fileData length] == 0) {
        return NO; // TODO error condition
    }
    
    // Convert the data to a string
    NSString *fileContents = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
    
    if (fileContents == nil) {
        return NO; // TODO error condition
    }
    
    // FIXME whitespace can vary
    NSRange range = [fileContents rangeOfString:@"gpgsign = true"];
    
    return (range.location != NSNotFound);
}

- (BOOL)homebrewInstalled {
    return [NSFileManager.defaultManager isReadableFileAtPath:@"/opt/homebrew/bin/brew"];
}

- (BOOL)pkgxInstalled {
    //TODO need to check more locations
    return [NSFileManager.defaultManager isReadableFileAtPath:@"/usr/local/bin/pkgx"];
}

- (IBAction)createSSHPrivateKey:(id)sender {
    id path = [NSString stringWithFormat:@"%@/.ssh/id_rsa", NSFileManager.defaultManager.homeDirectoryForCurrentUser.path];
    NSArray *arguments = @[@"-t", @"rsa", @"-b", @"4096", @"-f", path, @"-N", @""];
    
    if (run(@"/usr/bin/ssh-keygen", arguments, nil)) {
        [self.sshSwitch setEnabled:NO];
        [self calculateSecurityRating];
    } else {
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"ssh-keygen failed";
        [alert runModal];
        [self.sshSwitch setState:NSControlStateValueOff];
    }
}

- (IBAction)createSSHPassPhrase:(id)sender {
    
    [NSApp.mainWindow beginSheet:self.sshPassphraseWindow completionHandler:^(NSModalResponse returnCode) {
        
        //TODO should not remove passphrase window until complete in case of failure
        
        if (returnCode != NSModalResponseOK) {
            [self.sshPassPhraseSwitch setState:NSControlStateValueOff];
            return;
        }

        id path = [NSString stringWithFormat:@"%@/.ssh/id_rsa", NSFileManager.defaultManager.homeDirectoryForCurrentUser.path];
    
        id passphrase = self.sshPassphraseTextField.stringValue;
    
        NSPipe *pipe = [NSPipe pipe];
    
        if (!run(@"/usr/bin/ssh-keygen", @[@"-p", @"-N", passphrase, @"-f", path], pipe)) {
            id stderr = [NSString stringWithUTF8String:[pipe.fileHandleForReading readDataToEndOfFile].bytes];
    
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"ssh-keygen failed";
            alert.informativeText = stderr;
            [alert runModal];
            [self.sshPassPhraseSwitch setState:NSControlStateValueOff];
            return;
        }
        
        [self.sshPassphraseTextField setStringValue:@""]; // get it out of memory ASAP
        [self.sshPassPhraseSwitch setEnabled:NO];
        [self calculateSecurityRating];
    }];
}

- (IBAction)createSSHPassPhraseStep2:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Your passphrase won’t be stored";
    alert.informativeText = @"Please print the Emergency Kit and save it securely, or confirm you have another way to restore your credentials.\n\nDon’t worry—losing your SSH credentials is (usually) recoverable.";
    [alert addButtonWithTitle:@"Print Kit"];
    [alert addButtonWithTitle:@"Proceed Without Kit"];
    [alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.sshPassphraseWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSModalResponseCancel) {
            [NSApp endSheet:self.sshPassphraseWindow returnCode:NSModalResponseOK];
        }
    }];
}

- (IBAction)signCommits:(id)sender {
    
    [NSApp.mainWindow beginSheet:self.gpgPassphraseWindow completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSModalResponseOK) {
            [self.gpgSignSwitch setState:NSControlStateValueOff];
        } else {
            [self calculateSecurityRating];
        }
    }];
}

- (IBAction)modalCancel:(NSButton *)sender {
    [NSApp endSheet:[sender window]];
}

- (IBAction)modalOK:(NSButton *)sender {
    [NSApp endSheet:[sender window] returnCode:NSModalResponseOK];
}


- (IBAction)openPkgxHome:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://pkgx.sh"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)openHomebrewHome:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://brew.sh"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (IBAction)openGitHub:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://github.com/pkgxdev/teaBASE"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}


//TODO error handling
- (void)installPkgx:(id)sender {
    LAContext *context = [[LAContext alloc] init];
    NSError *authError = nil;
    NSString *reasonString = @"Authenticate to copy the file to /usr/local/bin";

    if (![context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError]) {
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                localizedReason:reasonString
                          reply:^(BOOL success, NSError * _Nullable error) {
            if (success) {
                // Touch ID authentication successful, proceed with file copy
                dispatch_async(dispatch_get_main_queue(), ^{
                    id src = [[NSBundle bundleForClass:[self class]] pathForResource:@"pkgx" ofType:@"Executables"];
                    id dst = @"/usr/local/bin/pkgx";
                    src = [NSURL fileURLWithPath:src];
                    dst = [NSURL fileURLWithPath:dst];
                    
                    id err = nil;
                    [[NSFileManager defaultManager] copyItemAtURL:src toURL:dst error:&err];
                    
                    if (!err) {
                        [self.pkgxSwitch setEnabled:NO];
                    }
                });
            } else {
                // Authentication failed, handle error
                NSLog(@"Authentication failed: %@", error.localizedDescription);
            }
        }];
    } else {
        // Biometrics not available, fallback to other authentication methods
        NSLog(@"Biometrics not available: %@", authError.localizedDescription);
    }
}

@end

@implementation teaBASE (NSTableViewDataSource)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return 5;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        switch (row) {
            case 0:
                return @"git wip";
            case 1:
                return @"git ai";
            case 2:
                return @"Fork";
            case 3:
                return @".DS_Ignore";
            case 4:
                return @"git afm";
        }
    } else if ([tableColumn.identifier isEqualToString:@"type"]) {
        switch (row) {
            case 0:
                return @"Alias to commit all changes w/message “wip”";
            case 1:
                return @"AI generate your commit messages";
            case 2:
                return @"GUI complement to git CLI";
            case 3:
                return @"Never commit a .DS_Store file again via global ignore";
            case 4:
                return @"Alias to amend‑commit everything to the previous commit";
        }
    }
    return @"";
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 20;
}

@end


@interface VerticallyAlignedTextFieldCell: NSTextFieldCell
@end

@implementation VerticallyAlignedTextFieldCell

- (NSRect)titleRectForBounds:(NSRect)theRect {
    NSRect titleFrame = [super titleRectForBounds:theRect];
    NSSize titleSize = [[self attributedStringValue] size];
    titleFrame.origin.y = theRect.origin.y - .5 + (theRect.size.height - titleSize.height) / 2.0;
    return titleFrame;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSRect titleRect = [self titleRectForBounds:cellFrame];
    [[self attributedStringValue] drawInRect:titleRect];
}

@end
