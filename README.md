copy-imap-acls
==============

Script to copy IMAP mail access control lists from one user to another

This tool is usually needed when there are shared mail folders. When creating a new mail user, sometimes you need to add the same permissions as another user. This script eases this task. In addition to copy the ACL flags it may:

- subscribe to the same folders as the original user
- mark current mail as seen

Usage
-----

copy\_imap\_acls.pl [--help] [--host=localhost] [--quiet] [--inspect-users] user\_src user\_dst

  --inspect-users: This copies the inbox ACLs too. That will allow the new user access to the origin user folders. Usually you don't want to do this. 
  
Requirements
------------

- Perl
- Perl Modules: Mail::IMAPClient , Term::ReadKey

Installation
------------

In debian and derivatives do:

 # apt-get install libmail-imapclient-perl libterm-readkey-perl
 
Other flavours of linux will require similar packages. It should work in Windows systems too, Perl and Perl modules for these systems are available.

Tested on
---------

This script has been tested on those OS:

- Debian Squeeze
- Ubuntu 13.10

The supported IMAP servers are the same as Mail::IMAPClient. It just has been tested on:

- cyrus-imapd 2.2
