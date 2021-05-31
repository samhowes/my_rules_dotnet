package dotnet

import (
	"fmt"
	"github.com/samhowes/my_rules_dotnet/gazelle/dotnet/util"
	"log"
	"strings"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/repo"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
	bzl "github.com/bazelbuild/buildtools/build"
)

// ============ resolve.Resolver implementation ============

// Imports returns a list of ImportSpecs that can be used to import the rule
// r. This is used to populate RuleIndex.
//
// If nil is returned, the rule will not be indexed. If any non-nil slice is
// returned, including an empty slice, the rule will be indexed.
func (d *dotnetLang) Imports(c *config.Config, r *rule.Rule, f *rule.File) []resolve.ImportSpec {
	info := getInfo(c)
	if info.Project != nil && info.Project.Rule.Name() == r.Name() {
		l := fmt.Sprintf(info.Project.FileLabel.String())
		return []resolve.ImportSpec{{
			Lang: dotnetName,
			Imp:  l,
		}}
	}

	return []resolve.ImportSpec{{
		Lang: dotnetName,
		Imp:  label.Label{Name: r.Name(), Pkg: f.Pkg}.String(),
	}}
}

type projectDep struct {
	Label     label.Label
	Comments  []string
	IsPackage bool
}

// Resolve translates imported libraries for a given rule into Bazel
// dependencies. Information about imported libraries is returned for each
// rule generated by language.GenerateRules in
// language.GenerateResult.Imports. Resolve generates a "deps" attribute (or
// the appropriate language-specific equivalent) for each import according to
// language-specific rules and heuristics.
func (d *dotnetLang) Resolve(c *config.Config, ix *resolve.RuleIndex, rc *repo.RemoteCache, r *rule.Rule, importsRaw interface{}, from label.Label) {
	var missing []bzl.Comment
	var deps []bzl.Expr
	for _, depRaw := range importsRaw.([]interface{}) {
		dep := depRaw.(*projectDep)
		comments := make([]bzl.Comment, len(dep.Comments))

		for i, c := range dep.Comments {
			comments[i] = bzl.Comment{Token: util.CommentErr(c)}
		}
		l, comments := findDep(c, ix, dep, comments, from)

		if l == nil {
			missing = append(missing, comments...)
		} else {
			// not sure why gazelle doesn't do this automatically...
			if from.Repo == l.Repo {
				l.Repo = ""
			}

			dExpr := bzl.StringExpr{
				Value:    l.String(),
				Comments: bzl.Comments{Before: comments},
			}
			deps = append(deps, &dExpr)
		}
	}

	if expr := util.ListWithComments(deps, missing); expr != nil {
		r.SetAttr("deps", expr)
	}
}

func findDep(c *config.Config, ix *resolve.RuleIndex, dep *projectDep, comments []bzl.Comment, from label.Label) (*label.Label, []bzl.Comment) {
	if dep.Label == label.NoLabel {
		return nil, comments
	}
	if dep.IsPackage {
		return &dep.Label, comments
	}
	spec := resolve.ImportSpec{
		Lang: dotnetName,
		Imp:  dep.Label.String(),
	}
	results := ix.FindRulesByImportWithConfig(c, spec, dotnetName)
	if len(results) > 1 {
		labels := make([]string, len(results))
		for i, r := range results {
			labels[i] = r.Label.String()
		}
		log.Panicf("ambigous project path found resolving import for %s.\nThis should not happen, please file an issue. \n"+
			"  requested import: %s\n"+
			"  results: %s", from.String(), dep.Label.String(), strings.Join(labels, "\n    "))
	} else if len(results) == 0 {
		c := fmt.Sprintf("could not find project file at %s", dep.Label.String())
		comments = append(comments, bzl.Comment{Token: util.CommentErr(c)})
		return nil, comments
	}
	return &results[0].Label, comments
}
