#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long;
use URI::Escape;
use HTTP::Date qw(str2time time2isoz);
use OsmApi;

my $username;
my $uid;
my $since_date = "2001-01-01T00:00:00Z";
my $to_date;
my $output_dirname;

GetOptions(
    "username|u=s" => \$username,
    "id|uid=i" => \$uid,
    "from|since=s" => \$since_date,
    "to=s" => \$to_date,
    "output=s" => \$output_dirname
) or die("Error in command line arguments\n");

my $user_arg;
if (defined($username))
{
    if (defined($uid))
    {
        die "both user name and id supplied, need to have only one of them";
    }
    else
    {
        $user_arg = "display_name=" . uri_escape($username);
        $output_dirname = "changesets_$username" unless defined($output_dirname);
    }
}
else
{
    if (defined($uid))
    {
        $user_arg = "user=" . uri_escape($uid);
        $output_dirname = "changesets_$uid" unless defined($output_dirname);
    }
    else
    {
        die "neither user name nor id supplied, need to have one of them";
    }
}

mkdir $output_dirname unless -d $output_dirname;

my %visited_changesets = ();

# metadata download phase
while (1)
{
    my $time_arg = "";
    if (defined($to_date))
    {
        $time_arg = "time=" . uri_escape($since_date) . "," . uri_escape($to_date);
    }
    else
    {
        $time_arg = "time=" . uri_escape($since_date);
    }

    my $resp = OsmApi::get("changesets?$user_arg&$time_arg");
    if (!$resp->is_success) {
        die "changeset metadata fetch failed: " . $resp->status_line;
    }

    my $list_fh;
    my $list = $resp->content;
    my $list_source = \$list;

    my $id;
    my $top_created_at;
    my $created_at;
    my $closed_at;
    my $new_changesets_count = 0;
    open($list_fh, '<', $list_source);
    while (<$list_fh>)
    {
        next unless /<changeset/;
        /id="(\d+)"/;
        $id = $1;
        /created_at="([^"]*)"/;
        $created_at = $1;
        next unless defined($id) && defined($created_at);
        $top_created_at = $created_at unless defined($top_created_at);
        /closed_at="([^"]*)"/;
        $closed_at = $1;
        print "$id $created_at $closed_at\n";
        if (!$visited_changesets{$id}) {
            $new_changesets_count++;
            $visited_changesets{$id} = 1;
        }
    }
    close $list_fh;

    if (defined($top_created_at))
    {
        $_ = $top_created_at;
        tr/-://d;
        my $list_filename = "$output_dirname/list_$_.xml";
        open($list_fh, '>', $list_filename) or die "can't open changeset list file '$list_filename' for writing";
        print $list_fh $list;
        close $list_fh;
    }

    last if $new_changesets_count == 0;

    $to_date = time2isoz(str2time($created_at) + 1);
    $to_date =~ s/ /T/;
}
