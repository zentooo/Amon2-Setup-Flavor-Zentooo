use strict;
use warnings FATAL => 'all';
use utf8;

package Amon2::Setup::Flavor::Zentooo;
use parent qw(Amon2::Setup::Flavor::Basic);
use File::Path ();

sub create_makefile_pl {
    my ($self, $prereq_pm) = @_;

    $self->SUPER::create_makefile_pl(
        +{
            %{ $prereq_pm || {} },
            'String::CamelCase' => '0.02',
            'Module::Pluggable::Object' => 0, # was first released with perl v5.8.9
        },
    );
}

sub write_static_files {
    my ($self, $base) = @_;
    $base ||= 'static';

    $self->write_file("$base/robots.txt", '');

    $self->write_file("$base/js/main.js", <<'...');
(function() {
    function $(id) {
        return document.getElementById(id);
    }
    document.addEventListener("DOMContentLoaded", function() {
    }, false);
})();
...

    $self->write_file("$base/css/main.css", <<'...');
html {
}

body {
}
...
}

sub write_templates {
    my $self = shift;

    $self->SUPER::write_templates("tmpl/");
}

sub run {
    my $self = shift;

    $self->SUPER::run();

    $self->write_file('app.psgi', <<'...', +{ header => $self->psgi_header });
<% $header %>
use <% $module _ '::Web' %>;
use Plack::App::File;
use Plack::Util;

my $basedir = File::Spec->rel2abs(dirname(__FILE__));
{
    my $c = <% $module _ '::Web' %>->new();
    $c->setup_schema();
}
builder {
    enable 'Plack::Middleware::Static',
        path => qr{^(?:/robots\.txt|/favicon\.ico)$},
        root => File::Spec->catdir(dirname(__FILE__), 'static');
    enable 'Plack::Middleware::ReverseProxy';

    mount '/static/' => Plack::App::File->new(root => File::Spec->catdir($basedir, 'static'));
    mount '/' => <% $module %>::Web->to_app();
};
...

    $self->write_file('tmpl/error.tt', <<'...');
[% WRAPPER 'include/layout.tt' %]

<div class="alert-message error">
    An error occurred : [% message %]
</div>

[% END %]
...

    $self->write_file('tmpl/index.tt', <<'...');
[% WRAPPER 'include/layout.tt' %]

<section>
    <h1>Hello, hello, hello</h1>
</section>

[% END %]
...

    $self->write_file('tmpl/include/layout.tt', <<'...');
<!DOCTYPE HTML>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title></title>
</head>
<body>
[% content %]
</body>
</html>
...

    $self->write_file('tmpl/include/sidebar.tt', <<'...');
<ul>
    <li><a href="[% uri_for('/') %]">Home</a></li>
</ul>
...

    $self->write_file("t/00_compile.t", <<'...');
use strict;
use warnings;
use Test::More;

use_ok $_ for qw(
    <% $module %>
    <% $module %>::Web
);

done_testing;
...
}

sub create_web_pms {
    my ($self) = @_;

    my $moniker = "Web";

    $self->write_file("lib/<<PATH>>/$moniker.pm", <<'...', { xslate => $self->create_view(tmpl_path => 'tmpl/'), moniker => $moniker });
package <% $module %>::<% $moniker %>;
use strict;
use warnings;
use utf8;
use parent qw(<% $module %> Amon2::Web);
use File::Spec;

# dispatcher
use <% $module %>::<% $moniker %>::Dispatcher;
sub dispatch {
    return <% $module %>::<% $moniker %>::Dispatcher->dispatch($_[0]) or die "response is not generated";
}

<% $xslate %>

# load plugins
__PACKAGE__->load_plugins(
    'Web::FillInFormLite',
);

sub show_error {
    my ( $c, $msg, $code ) = @_;
    my $res = $c->render( 'error.tt', { message => $msg } );
    $res->code( $code || 500 );
    return $res;
}

# for your security
__PACKAGE__->add_trigger(
    AFTER_DISPATCH => sub {
        my ( $c, $res ) = @_;

        # http://blogs.msdn.com/b/ie/archive/2008/07/02/ie8-security-part-v-comprehensive-protection.aspx
        $res->header( 'X-Content-Type-Options' => 'nosniff' );

        # http://blog.mozilla.com/security/2010/09/08/x-frame-options/
        $res->header( 'X-Frame-Options' => 'DENY' );

        # Cache control.
        $res->header( 'Cache-Control' => 'private' );
    },
);

1;
...
        $self->write_file("lib/<<PATH>>/$moniker/Dispatcher.pm", <<'...', {moniker => $moniker});
package <% $module %>::<% $moniker %>::Dispatcher;
use strict;
use warnings;
use utf8;
use Router::Simple::Declare;
use Mouse::Util qw(get_code_package);
use String::CamelCase qw(decamelize);
use Module::Pluggable::Object;

# define roots here.
my $router = router {
    # connect '/' => {controller => 'Root', action => 'index' };
};

my @controllers = Module::Pluggable::Object->new(
    require     => 1,
    search_path => ['<% $module %>::<% $moniker %>::C'],
)->plugins;
{
    no strict 'refs';
    for my $controller (@controllers) {
        my $p0 = $controller;
        $p0 =~ s/^<% $module %>::<% $moniker %>::C:://;
        my $p1 = $p0 eq 'Root' ? '' : decamelize($p0) . '/';

        for my $method (sort keys %{"${controller}::"}) {
            next if $method =~ /(?:^_|^BEGIN$|^import$)/;
            my $code = *{"${controller}::${method}"}{CODE};
            next unless $code;
            next if get_code_package($code) ne $controller;
            my $p2 = $method eq 'index' ? '' : $method;
            my $path = "/$p1$p2";
            $router->connect($path => {
                controller => $p0,
                action     => $method,
            });
            print STDERR "map: $path => ${p0}::${method}\n" unless $ENV{HARNESS_ACTIVE};
        }
    }
}

sub dispatch {
    my ($class, $c) = @_;
    my $req = $c->request;
    if (my $p = $router->match($req->env)) {
        my $action = $p->{action};
        $c->{args} = $p;
        "@{[ ref Amon2->context ]}::C::$p->{controller}"->$action($c, $p);
    } else {
        $c->res_404();
    }
}

1;
...

        $self->write_file("lib/<<PATH>>/$moniker/C/Root.pm", <<'...', {moniker => $moniker});
package <% $module %>::<% $moniker %>::C::Root;
use strict;
use warnings;
use utf8;

sub index {
    my ($class, $c) = @_;
    $c->render('index.tt');
}

1;
...
}

1;
