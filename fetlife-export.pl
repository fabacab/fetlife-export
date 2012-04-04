#!/usr/bin/perl -w

use strict;
use WWW::Mechanize;
use Term::ReadKey;
use LWP::Simple qw/getstore/;
use File::Basename;
use File::Path;
use HTML::TreeBuilder;
use String::Escape;
use Unicode::Escape;

$|++;

my $mech = new WWW::Mechanize( stack_depth => 0 ); # No need for history, save memory!
my $username = shift or &usage;
my $dir = shift || ".";
print "Password: ";
ReadMode('noecho');
my $password = ReadLine 0;
ReadMode('normal');
chomp $password;
print "\n";

&login($username, $password);
my $id = &getId();
print "userID: $id\n";

mkpath("$dir/fetlife");

&downloadProfile();
&downloadConversations();
&downloadWall();
&collectLinksInActivityFeed();

sub downloadProfile {
  print "Loading profile: .", "\n";
  $mech->get("https://fetlife.com/users/$id");
  my $tree;
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());

  open(DATA, "> $dir/fetlife/$id.html") or die "Can't write $id.html: $!";
  if (open(FILE, "< templates/header.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  print DATA $tree->look_down( id => 'profile' )->as_HTML(undef, "\t", {}), "\n\n";
  if (open(FILE, "< templates/footer.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }

  close DATA;
  $tree->delete();
}

sub downloadConversations {
  mkdir "$dir/fetlife/conversations";

  print "Loading conversations: .";
  $mech->get("https://fetlife.com/conversations/all");
  my @links = $mech->find_all_links( url_regex => qr{/conversations/\d+} );
  while (my $next = $mech->find_link( url_regex => qr{/conversations/all\?page=(\d)}, text_regex => qr/Next/ )) {
      print ".";
      $mech->get($next);
      push @links, $mech->find_all_links( url_regex => qr{/conversations/\d+} );
  }

  my $num = @links;
  my $s = &s($num);
  my $i = 1;
  print " $num conversation$s found.\n";
  return unless $num;
  foreach my $page (@links) {
    print "$i/$num\r";

    &getMessages($page);

    $i++;
  }
}

sub getMessages {
  my $page = shift;
  my $tree;
  $mech->get($page);
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  my $x = basename($page->url());
  my @y = split(/#/, $x);
  my $name = $y[0];

  open(DATA, "> $dir/fetlife/conversations/$name.html") or die "Can't write $name.html";
  print DATA "<!-- FetLife Exporter Source URL: " . $page->url_abs() . " -->", "\n\n";
  print DATA $tree->look_down( id => 'messages' )->as_HTML(undef, "\t", {}), "\n\n";

  close DATA;
  $tree->delete();
}

# TODO: This downloads only a given user's wall. However, due to the nature
#       of the way wall messaging works, we need to download the others user's
#       walls to get the other half of the conversation, too.
sub downloadWall {
  print "Loading wall: .";

  # Grab the first page of my wall.
  $mech->get("https://fetlife.com/users/$id/wall_posts");

  my @links = $mech->find_all_links( url_regex => qr/wall_to_wall/ );

  while (my $next = $mech->find_link( url_regex => qr{users/$id/wall_posts\?page}, text_regex => qr/^Next/ )) {
    print ".";
    $mech->get($next);
    push @links, $mech->find_all_links( url_regex => qr/wall_to_wall/ );
  }
  @links = &filterLinksList(@links);

  my $num = @links;
  my $s = &s($num);
  print " $num wall-to-wall$s found.\n";

  if ($num) {
    downloadWallToWall($num, @links);
  }
}

sub downloadWallToWall ($$) {
  mkdir "$dir/fetlife/wall_to_wall";

  my $num = shift;
  my @links = @_;

  print "Downloading $num wall-to-walls...\n";

  my $i = 1;
  foreach my $page (@links) {
    print "$i/$num\r";

    &getWallToWall($page);

    $i++;
  }
}

sub getWallToWall {
  my $page = shift;
  my $tree;

  $mech->get($page);

  my $name = $mech->title();

  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());

  open(DATA, "> $dir/fetlife/wall_to_wall/$name.html") or die "Can't write wall.html";
  print DATA "<!-- FetLife Exporter Source URL: " . $page->url_abs() . " -->", "\n\n";
  print DATA $tree->look_down( id => 'wall_posts' )->as_HTML(undef, "\t", {}), "\n\n";

  close DATA;
  $tree->delete();
}

# Traverses a user's activity feed, collecting links to download.
# TODO: Refactor this so the `downloadStatuses()` and `downloadGroupPosts()` functions
#       aren't actually nested here.
sub collectLinksInActivityFeed {
  print "Loading activity feed: .";

  $mech->get("https://fetlife.com/users/$id/activity");

  # Only links to one's own statuses are FQURIs, so use absolute (server-relative) URI.
  my @statuses    = $mech->find_all_links( url_regex => qr{/users/\d+/statuses/\d+$} );
  my @pictures    = $mech->find_all_links( url_regex => qr{https?://fetlife.com/users/\d+/pictures/\d+$} );
  my @writings    = $mech->find_all_links( url_regex => qr{https?://fetlife.com/users/\d+/posts/\d+$} );
  my @group_posts = $mech->find_all_links( url_regex => qr{https?://fetlife.com/groups/\d+/group_posts/\d+$} );

  # Catch errors, but crudely.
  eval {
    while (my $next = $mech->find_link( url_regex => qr{/users/$id/activity/more\?page}, text_regex => qr/view more/ )) {
      print ".";
      $mech->get($next);

      #### FetLife returns straight-up jQuery, so clean this out before parsing.
      #### TODO: Can we refactor this? It feels kludgy.
      # Split into lines.
      my @x = split("\n", $mech->content);

      # If this is the end of the feed, we'll only get 2 lines back with which we can do nothing.
      # Otherwise, we'll get three lines.
      if (3 == scalar(grep $_, @x)) {
        # Ignore the first line.

        # Clean the second line.
        ## Extract the JavaScript and Unicode-encoded text from the jQuery commands.
        ### Cut out the first 24 characters, which are always: `$("#mini_feed").append("`
        my $x1 = substr($x[1], 24);
        ### Cut out the last 3 characters, which are always: `");`
        $x1 = substr($x1, 0, -3);
        $x1 = Unicode::Escape::unescape($x1, 'UTF-8');
        $x1 = String::Escape::unbackslash($x1);

        my $x2 = substr($x[2], 23);
        $x2 = substr($x2, 0, -3);
        $x2 = String::Escape::unbackslash($x2);

        # Concatenate the cleaned-up lines together.
        my $html = Encode::decode_utf8($x1 . $x2);
        $mech->update_html($html);
      }

      push @statuses, $mech->find_all_links( url_regex => qr{/users/\d+/statuses/\d+$} );
      push @pictures, $mech->find_all_links( url_regex => qr{https?://fetlife.com/users/\d+/pictures/\d+$} );
      push @writings, $mech->find_all_links( url_regex => qr{https?://fetlife.com/users/\d+/posts/\d+$} );
      push @group_posts, $mech->find_all_links( url_regex => qr{https?://fetlife.com/groups/\d+/group_posts/\d+$} );
    }
  };
  # Did we hit an error while trying to download the activity feed?
  # TODO: This error handling should be a bit more robust, methinks.
  if ($@) {
    print "$0 encountered an error loading activity feed for $username (ID $id): $@";
  }

  @statuses    = &filterLinksList(@statuses);
  @pictures    = &filterLinksList(@pictures);
  @writings    = &filterLinksList(@writings);
  @group_posts = &filterLinksList(@group_posts);

  # Count how many statuses were found.
  my $snum = @statuses;
  my $s = &s($snum, 1);
  print " $snum status$s found.\n";

  # Count how many pictures were found.
  my $pnum = @pictures;
  $s = &s($pnum);
  print " $pnum picture$s found.\n";

  # Count how many writings were found.
  my $wnum = @writings;
  $s = &s($wnum);
  print " $wnum writing$s found.\n";

  # Count how many group threads were found.
  my $gnum = @group_posts;
  $s = &s($gnum);
  print " $gnum group thread$s found.\n";

  # If we found things to download, go download them.
  if ($snum) {
    downloadStatuses($snum, @statuses);
  }

  if ($pnum) {
    downloadPics($pnum, @pictures);
  }

  if ($wnum) {
    downloadWritings($wnum, @writings);
  }

  if ($gnum) {
    downloadGroupPosts($gnum, @group_posts);
  }
}

sub downloadStatuses ($$) {
  mkdir "$dir/fetlife/statuses";

  my $num = shift;
  my @links = @_;

  print "Downloading $num statuses...\n";

  my $i = 1;
  foreach my $page (@links) {
    print "$i/$num\r";

    my $name = basename($page->url());
    unless ( -f "$dir/fetlife/statuses/$name.html" ) {
      &getStatus($page);
    }

    $i++;
  }
}

sub getStatus {
  my $page = shift;
  my $tree;
  my $name = basename($page->url());

  $mech->get($page);
  if (!$mech->success()) {
    print "$0: Error GETing $page";
    return;
  }

  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());

  # Strip out problematic HTML.
  my @comments = $tree->look_down( class => qr/status_comment/ );
  foreach my $comment (@comments) {
    $comment->attr( 'style', undef );
  }
  eval {
    $tree->look_down( class => qr/new_comment/ )->delete();
  };
  # If we've hit an error, we don't write a file, so we may catch it on next round.
  if ($@) {
    print "$0: Oh no, Molly! Error on " . $page->url() . " $@\n";
  } else {
    open(DATA, "> $dir/fetlife/statuses/$name.html") or die "Can't write $name.html";
    if (open(FILE, "< templates/header.html")) {
      while (<FILE>) {
          print DATA $_;
      }
      close FILE;
    }
    if (open(FILE, "< templates/statuses-top.html")) {
      while (<FILE>) {
          print DATA $_;
      }
      close FILE;
    }
    print DATA "<!-- FetLife Exporter Source URL: " . $page->url_abs() . " -->", "\n\n";
    print DATA $tree->look_down( id => "status_$name" )->as_HTML(undef, "\t", {}), "\n\n";
    if (open(FILE, "< templates/statuses-bottom.html")) {
      while (<FILE>) {
          print DATA $_;
      }
      close FILE;
    }
    if (open(FILE, "< templates/footer.html")) {
      while (<FILE>) {
          print DATA $_;
      }
      close FILE;
    }
    close DATA;
  }

  $tree->delete();
}

sub downloadGroupPosts ($$) {
  mkdir "$dir/fetlife/group_posts";

  my $num = shift;
  my @links = @_;

  print "Downloading $num group posts...\n";

  my $i = 1;
  foreach my $page (@links) {
    print "$i/$num\r";

    my $name = basename($page->url());
    unless ( -f "$dir/fetlife/group_posts/$name.html" ) {
      &getGroupThread($page);
    }

    $i++;
  }
}

sub getGroupThread {
  my $page = shift;
  my $tree;
  my $name = basename($page->url());

  # Grab the first page of the group thread.
  $mech->get($page);

  # Download the first page.
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());

  # TODO: Edit HTML so `#comments` ID isn't repeated and pagination links are intra-page.

  open(DATA, "> $dir/fetlife/group_posts/$name.html") or die "Can't write $name.html";
  if (open(FILE, "< templates/header.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  if (open(FILE, "< templates/group_posts-top.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  print DATA "<!-- FetLife Exporter Source URL: " . $page->url_abs() . " -->", "\n\n";
  print DATA $tree->look_down( class => qr{group_post} )->as_HTML(undef, "\t", {}), "\n\n";
  my $comments = $tree->look_down( id => 'comments' );
  if ($comments) {
    print DATA '<br /><div id="group_post_comments_container">'; # FetLife's HTML.
    print DATA $tree->look_down( id => 'comments' )->as_HTML(undef, "\t", {}), "\n\n";
  }
  $tree->delete();

  # Also download comments on next pages.
  while (my $next = $mech->find_link( url_regex => qr{groups/\d+/group_posts/\d+\?page}, text_regex => qr/^Next/ )) {
    $mech->get($next);

    $tree = HTML::TreeBuilder->new();
    $tree->ignore_unknown(0);
    $tree->parse($mech->content());

    print DATA $tree->look_down( id => 'comments' )->as_HTML(undef, "\t", {}), "\n\n";
    print DATA '</div><!-- /#group_post_comments_container -->'; # FetLife's HTML.

    $tree->delete();
  }
  if (open(FILE, "< templates/group_posts-bottom.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  if (open(FILE, "< templates/footer.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }

  close DATA;
}

sub downloadWritings ($$) {
  mkdir "$dir/fetlife/posts";

  my $num = shift;
  my @links = @_;

  print "Downloading $num posts...\n";

  my $i = 1;
  foreach my $page (@links) {
    print "$i/$num\r";

    my $name = basename($page->url());
    unless ( -f "$dir/fetlife/posts/$name.html" ) {
      &getPost($page);
    }

    $i++;
  }
}

sub getPost {
  my $page = shift;
  my $tree;
  $mech->get($page);
  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());
  my $name = basename($page->url());
  if (!$tree->look_down( id => 'post_content' )) {
    print "$0: Oh no, Molly! Error on " . $page->url() . "\n";
    return;
  }
  open(DATA, "> $dir/fetlife/posts/$name.html") or die "Can't write $name.html: $!";
  if (open(FILE, "< templates/header.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  if (open(FILE, "< templates/posts-top.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  print DATA "<!-- FetLife Exporter Source URL: " . $page->url_abs() . " -->", "\n\n";
  print DATA $tree->look_down( id => 'post_content' )->as_HTML(undef, "\t", {}), "\n\n";
  print DATA $tree->look_down( id => 'comments' )->as_HTML(undef, "\t", {}), "\n\n";
  if (open(FILE, "< templates/posts-bottom.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  if (open(FILE, "< templates/footer.html")) {
    while (<FILE>) {
        print DATA $_;
    }
    close FILE;
  }
  close DATA;
  $tree->delete();
}

sub downloadPics ($$) {
  mkdir "$dir/fetlife/pictures";

  my $num = shift;
  my @links = @_;

  print "Downloading $num pictures...\n";

  my $i = 1;
  foreach my $page (@links) {
    print "$i/$num\r";

    &getImage($page);

    $i++;
  }
}

sub getImage {
  my $page = shift;
  my $tree;
  $mech->get($page);
  my $image = $mech->find_image( url_regex => qr{flpics.*_720\.jpg} );
  if (!$image) {
    print "$0: Oh no, Molly! Error on " . $page->url() . "\n";
    return;
  }
  my $name = basename($image->url());

  # Don't download images we've already grabbed.
  # TODO: Extend this so we don't download pages/threads we've already grabbed, either.
  unless ( -f "$dir/fetlife/pictures/$name" ) {
    getstore($image->url(), "$dir/fetlife/pictures/$name");
  }

  $tree = HTML::TreeBuilder->new();
  $tree->ignore_unknown(0);
  $tree->parse($mech->content());

  my $picture = $tree->look_down( id => "picture" );
  my $pic_img = $picture->find_by_tag_name( 'img' );
  $pic_img    = \$pic_img->attr( 'src', $name );

  open(DATA, "> $dir/fetlife/pictures/$name.html") or die "Can't write $name.html: $!";
  print DATA "<!-- FetLife Exporter Source URL: " . $page->url_abs() . " -->", "\n\n";
  print DATA $picture->as_HTML(undef, "\t", {}), "\n\n";
  print DATA $tree->look_down( id => "comments" )->as_HTML(undef, "\t", {}), "\n\n";
  close DATA;

  $tree->delete();
}

sub filterLinksList {
  my %uniq = map { $_->url_abs(), $_ } @_;
  return values %uniq;
}

sub getId {
  my $link = $mech->find_link( text_regex => qr/View Your Profile/i );
  die "Failed to find profile link!" unless $link;
  if ($link->url() =~ m{/(\d+)$}) {
    return $1;
  } else {
    die "Failed to get user ID out of profile link: " . $link->url();
  }
}

sub login {
  my ($username, $password) = @_;

  $mech->get( "https://fetlife.com/login" );
  $mech->form_with_fields( qw/nickname_or_email password/ );
  $mech->field( 'nickname_or_email' => $username );
  $mech->field( 'password' => $password );
  my $res = $mech->submit();
  die "Login failed!" unless $res->is_success;
}

sub usage {
  print "$0 <username> [<directory>]\n";
  exit 1;
}

sub s {
  my $num = shift;
  my $alt = shift;
  unless ($alt) { return $num == 1 ? "" : "s"; }
  else { return $num == 1 ? "" : "es"; }
}
