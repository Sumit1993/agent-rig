#!/bin/bash
# Find a gh call in a Bash command the way the shell would: outside quotes and heredoc
# bodies, in command position. Regexes over raw text misfired on quoted and heredoc
# text (#136, #123). A gh call inside a double-quoted "$(...)" is not seen.

read -r -d '' _GH_SCAN_PL <<'PL'
use strict; use warnings;
my ($mode, $re) = @ARGV;
local $/; my $s = <STDIN>; $s = '' unless defined $s;
my $n = length $s;

sub sq_end { my $j = index($s, "'", $_[0] + 1); $j < 0 ? $n : $j + 1 }
sub heredoc_at {
  my $i = shift;
  return undef unless substr($s, $i, 2) eq '<<' && substr($s, $i + 2, 1) ne '<';
  pos($s) = $i;
  return [[$3, $1], pos($s)] if $s =~ /\G<<(-?)[ \t]*(['"]?)([A-Za-z_]\w*)\2/gc;
  undef;
}
sub heredoc_skip {
  my ($i, $pend) = @_;
  for my $h (@$pend) {
    while ($i < $n) {
      my $e = index($s, "\n", $i);
      my $line = $e < 0 ? substr($s, $i) : substr($s, $i, $e - $i);
      $i = $e < 0 ? $n : $e + 1;
      $line =~ s/^\s+|\s+$//g;
      last if $line eq $h->[0];
    }
  }
  @$pend = ();
  $i;
}
sub dq_end {
  my $i = $_[0] + 1;
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq '\\') { $i += 2; next }
    return $i + 1 if $c eq '"';
    if (substr($s, $i, 2) eq '$(') { $i = sub_end($i); next }
    $i++;
  }
  $n;
}
sub sub_end {
  my $i = $_[0] + 2; my $depth = 1; my @pend;
  while ($i < $n) {
    my $c = substr($s, $i, 1);
    if ($c eq "\n" && @pend) { $i = heredoc_skip($i + 1, \@pend); next }
    if ($c eq '\\') { $i += 2; next }
    if ($c eq "'") { $i = sq_end($i); next }
    if ($c eq '"') { $i = dq_end($i); next }
    if (substr($s, $i, 2) eq '$(') { $i = sub_end($i); next }
    if (my $h = heredoc_at($i)) { push @pend, $h->[0]; $i = $h->[1]; next }
    if ($c eq '(') { $depth++ }
    elsif ($c eq ')') { return $i + 1 if --$depth == 0 }
    $i++;
  }
  $n;
}

# Mask quoted text and heredoc bodies with '_' so offsets still line up with $s.
my $m = $s; my @pend; my $i = 0;
my $fill = sub { my ($a, $b) = @_; substr($m, $a, $b - $a) = substr($s, $a, $b - $a) =~ s/[^\n]/_/gr };
while ($i < $n) {
  my $c = substr($s, $i, 1);
  if ($c eq "\n" && @pend) { my $e = heredoc_skip($i + 1, \@pend); $fill->($i + 1, $e); $i = $e; next }
  if ($c eq '\\') { $fill->($i, $i + 2 > $n ? $n : $i + 2); $i += 2; next }
  if ($c eq "'") { my $e = sq_end($i); $fill->($i, $e); $i = $e; next }
  if ($c eq '"') { my $e = dq_end($i); $fill->($i, $e); $i = $e; next }
  if (my $h = heredoc_at($i)) { push @pend, $h->[0]; $i = $h->[1]; next }
  $i++;
}
exit 1 unless $m =~ /(?:^|[;&|(`])[ \t]*(?:[A-Za-z_]\w*=\S*[ \t]+)*($re)/m;
my $off = $-[1];

if ($mode eq 'prefix') { print substr($s, 0, $off); exit 0 }
if ($mode eq 'tail') { print substr($s, $off); exit 0 }
exit 0 unless $mode eq 'words';

# The words of the simple command at $off, unquoted, NUL-separated.
my ($w, $have) = ('', 0); $i = $off;
my $emit = sub { print $w, "\0" if $have; ($w, $have) = ('', 0) };
while ($i < $n) {
  my $c = substr($s, $i, 1);
  last if $c =~ /[;&|\n)]/;
  if ($c =~ /[ \t]/) { $emit->(); $i++; next }
  $have = 1;
  if ($c eq '\\') { $w .= substr($s, $i + 1, 1) if substr($s, $i + 1, 1) ne "\n"; $i += 2; next }
  if ($c eq "'") { my $e = sq_end($i); $w .= substr($s, $i + 1, $e - $i - 2); $i = $e; next }
  if (substr($s, $i, 2) eq '$(') { my $e = sub_end($i); $w .= substr($s, $i, $e - $i); $i = $e; next }
  if ($c eq '"') {
    my $e = dq_end($i); my $j = $i + 1;
    while ($j < $e - 1) {
      my $d = substr($s, $j, 1);
      if ($d eq '\\' && substr($s, $j + 1, 1) =~ /[\$`"\\\n]/) { $w .= substr($s, $j + 1, 1); $j += 2; next }
      if (substr($s, $j, 2) eq '$(') { my $f = sub_end($j); $w .= substr($s, $j, $f - $j); $j = $f; next }
      $w .= $d; $j++;
    }
    $i = $e; next;
  }
  $w .= $c; $i++;
}
$emit->();
PL

# gh_scan <prefix|tail|words> <perl-regex> < cmd. Fails when no gh call matches.
gh_scan() { command -v perl >/dev/null 2>&1 || return 1; LC_ALL=C perl -e "$_GH_SCAN_PL" "$@"; }

# The lines of the first heredoc in text, after its `<<TAG` and before the TAG line.
gh_heredoc_body() {
  local text="$1" open tag
  open=$(grep -oE "<<-?[\"']?[A-Za-z_][A-Za-z0-9_]*[\"']?" <<<"$text" | head -1)
  [ -n "$open" ] || return 1
  tag=$(sed -E "s/^<<-?[\"']?//; s/[\"']?\$//" <<<"$open")
  awk -v tag="$tag" '
    found && $0 ~ ("^[[:space:]]*" tag "[[:space:]]*$") { exit }
    found { print; next }
    !found && $0 ~ ("<<-?[\"'"'"']?" tag) { found=1 }
  ' <<<"$text"
}

# Expand a bare $NAME or ${NAME} from the last NAME=value assignment in prefix.
gh_expand_var() { # <prefix> <word>
  local cmd=$1 word=$2 name val pat
  [[ "$word" =~ ^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$ ]] || { printf '%s' "$word"; return; }
  name=${BASH_REMATCH[1]}
  pat="(^|[;&|[:space:]])${name}=(\"([^\"]*)\"|'([^']*)'|([^[:space:];&|]+))"
  val=""
  while [[ "$cmd" =~ $pat ]]; do
    val="${BASH_REMATCH[3]}${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
    cmd=${cmd#*"${BASH_REMATCH[0]}"}
  done
  if [ -n "$val" ]; then printf '%s' "$val"; else printf '%s' "$word"; fi
}

gh_resolve_path() { # <cwd> <path>
  local cwd=$1 f=$2
  case "$f" in \~/*|\~) f="$HOME${f#\~}" ;; esac
  case "$f" in /*) ;; *) [ -n "$cwd" ] && f="$cwd/$f" ;; esac
  printf '%s' "$f"
}
