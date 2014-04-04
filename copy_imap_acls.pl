#!/usr/bin/perl

use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Getopt::Long;
use Mail::IMAPClient;
use Term::ReadKey;

my $HOST = 'localhost';
my $USER = 'cyrus';
my $QUIET;
my $DEBUG;
my $INSPECT_USERS;
my $MAX_ERRORS = 5;

my $help;
GetOptions(
          help => \$help
        ,debug => \$DEBUG
        ,quiet => \$QUIET
     ,'host=s' => \$HOST
    ,'inspect-users' => \$INSPECT_USERS
);

my $usage = "$0 [--help] [--host=$HOST] [--quiet] "
            ."[--inspect-users] user_src user_dst\n";

my $USER_SRC = $ARGV[0];
my $USER_DST = $ARGV[1];

die "$usage\n"
    if !$USER_SRC || !$USER_DST;

my $IMAP;
my %ACL;

$| = 1;

###################################################################
#

sub ask {
    my ($question,$default) = @_;
    print "$question ";
    print "[$default]" if $default;
    print ": ";
    my $text = ReadLine(0);
    chomp $text;
    return ($text or $default);
}


sub ask_pass{
    ReadMode('noecho');
        my $text = ask(@_);
        ReadMode('normal');
        print "\n";
        return $text;
}



sub init {

    $USER = ask("Admin user for IMAP",$USER);
    my $pass = ask_pass("IMAP Password for user $USER");
    $IMAP = Mail::IMAPClient->new(
                        Server =>  $HOST,
                        User    => $USER,
                        Password=> $pass,
        );
    die "Cannot connect to $HOST as $USER\n"
        if !$IMAP || !$IMAP->IsAuthenticated;
}

sub get_acl {
    my ($folder,$user) = @_;

    my $key = "$user:$folder";

    return $ACL{$key} if $ACL{$key};

    print "Getting ACLS for $folder\n"  if $DEBUG;
    my $hash = $IMAP->getacl($folder) ;
    die "Error getting ACL for $folder $user "
                .$IMAP->LastError if $IMAP->LastError;
    if (!keys %$hash) {
        warn "WARNING: No ACLs found for folder $folder\n";
        return;
    }

    my $acl ;
    for my $user_list (sort keys %$hash) {
        print "$user_list $hash->{$user_list}\n" if $DEBUG;
        $ACL{"$user_list:$folder"}=$hash->{$user_list};
        $acl = $hash->{$user_list} if $user eq $user_list;
    }
    if (!exists $ACL{$key}) {
        $ACL{$key} = "";
    }
    return $acl;
}

sub set_acl {
    my ($folder, $user, $acl) = @_;

    my $key = "$user:$folder";
    if  ( exists $ACL{$key} && $ACL{$key} eq $acl ) {
        print "\t $folder: $acl already set.\n"   if $DEBUG;
        return;
    }
    print "set_acl $user $folder: $acl\n" if !$QUIET;

    $IMAP->setacl($folder,$user,$acl)
        or die "ERROR setting ACL for $folder $user : $acl\n"
            .$IMAP->LastError;

    $ACL{$key} = $acl;
}
sub connect_imap {
    my $user = shift or confess "Missing user";
    my $pass= ask_pass("IMAP password for $user");
    my $imap = Mail::IMAPClient->new(
                        Server =>  $HOST,
                        User    => $user,
                        Password=> $pass,
        );
    my $error = $@." " if $@;
    $error .= $imap->LastError if $imap;
    die "Cannot connect to $HOST as $user $error\n"
        if !$imap || $error || !$imap->IsAuthenticated;
    return $imap;
}

sub ask_yn{
    my ($text,$default) = @_;
    $default = 'y' if !$default;
    for (;;) {
        my $answer = ask($text,$default);
        next if !$answer;
        return 0 if $answer=~ /n/i;
        last if $answer=~ /y/i;
    }
    return 1;
}

sub subscribe {
    my ($user,$folders) = @_;
    my $subscribe = ask_yn("Subscribe $user to ".scalar(@$folders)." folders "
                            ."(y/n)");
    my $mark_seen = ask_yn("Mark all current messages in folders"
                            ." as seen (y/n)");

    return if !$subscribe && !$mark_seen;

    my $imap = connect_imap($user);

    my %subscribed = map { $_ => 1 } $imap->subscribed;
    print "Already subscribed to ".scalar keys(%subscribed)
        ." folders, checking anyway.\n" if scalar keys %subscribed;

    my $n_errors = 0;
    my ($n_subscribed, $n_marked) = ( 0,0 );
    my $time0 = time;
    my $time1 = $time0;
    for my $folder (@$folders) {
        if ($subscribe && !$subscribed{$folder}) {
            $imap->subscribe($folder) 
            or do {
                warn "Error subscribing to $folder :".$imap->LastError."\n";
                $n_errors++;
            };
            $n_subscribed++;
        }
        if ($mark_seen) {
           $imap->select($folder) 
                or do {
                    warn "Error selecting $folder :".$imap->LastError."\n";
                  $n_errors++;
                };
            my @unseen = $imap->unseen();
            if (scalar(@unseen)) {
                warn "Marking ".scalar(@unseen)." messages as seen in $folder "
                    if $DEBUG;
                $imap->see(@unseen);
                $n_marked+= scalar(@unseen);
            }
        }
        if ($n_errors > $MAX_ERRORS) {
            warn "\ngiving up\n";
            last;
        }
        if (time - $time1 > 5) {
            print ".";
            $time1 = time;
        }
    }
    print "\n" if time-$time0 >= 5;
    print "$n_subscribed folders subscribed.\n" if $subscribe;
    print "$n_marked messages marked.\n"        if $mark_seen;

}

###################################################################
init ();

my @folders = $IMAP->folders();
@folders = grep !/^user\./, @folders  unless $INSPECT_USERS;

die "No folders found\n"
    if !scalar @folders;

my @added_folders;

for my $folder (@folders) {
    my $acl = get_acl($folder, $USER_SRC);
    next if !$acl;

    set_acl($folder, $USER_DST, $acl);
    push @added_folders,($folder);
}

print scalar(@added_folders)." folders added to user $USER_DST.\n\n";
subscribe($USER_DST,\@added_folders);
