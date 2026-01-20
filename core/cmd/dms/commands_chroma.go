package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/alecthomas/chroma/v2"
	"github.com/alecthomas/chroma/v2/formatters/html"
	"github.com/alecthomas/chroma/v2/lexers"
	"github.com/alecthomas/chroma/v2/styles"
	"github.com/spf13/cobra"
	"github.com/yuin/goldmark"
	highlighting "github.com/yuin/goldmark-highlighting/v2"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/parser"
	ghtml "github.com/yuin/goldmark/renderer/html"
)

var (
	chromaLanguage string
	chromaStyle    string
	chromaInline   bool
	chromaMarkdown bool
)

var chromaCmd = &cobra.Command{
	Use:   "chroma [file]",
	Short: "Syntax highlight source code",
	Long: `Generate syntax-highlighted HTML from source code.

Reads from file or stdin, outputs HTML with syntax highlighting.
Language is auto-detected from filename or can be specified with --language.

Examples:
  dms chroma main.go
  dms chroma --language python script.py
  echo "def foo(): pass" | dms chroma -l python
  cat code.rs | dms chroma -l rust --style dracula
  dms chroma --markdown README.md
  dms chroma --markdown --style github-dark notes.md
  dms chroma list-languages
  dms chroma list-styles`,
	Args: cobra.MaximumNArgs(1),
	Run:  runChroma,
}

var chromaListLanguagesCmd = &cobra.Command{
	Use:   "list-languages",
	Short: "List all supported languages",
	Run: func(cmd *cobra.Command, args []string) {
		for _, name := range lexers.Names(true) {
			fmt.Println(name)
		}
	},
}

var chromaListStylesCmd = &cobra.Command{
	Use:   "list-styles",
	Short: "List all available color styles",
	Run: func(cmd *cobra.Command, args []string) {
		for _, name := range styles.Names() {
			fmt.Println(name)
		}
	},
}

func init() {
	chromaCmd.Flags().StringVarP(&chromaLanguage, "language", "l", "", "Language for highlighting (auto-detect if not specified)")
	chromaCmd.Flags().StringVarP(&chromaStyle, "style", "s", "monokai", "Color style (monokai, dracula, github, etc.)")
	chromaCmd.Flags().BoolVar(&chromaInline, "inline", false, "Output inline styles instead of CSS classes")
	chromaCmd.Flags().BoolVarP(&chromaMarkdown, "markdown", "m", false, "Render markdown with syntax-highlighted code blocks")

	chromaCmd.AddCommand(chromaListLanguagesCmd)
	chromaCmd.AddCommand(chromaListStylesCmd)
}

func runChroma(cmd *cobra.Command, args []string) {
	var source string
	var filename string

	// Read from file or stdin
	if len(args) > 0 {
		filename = args[0]
		content, err := os.ReadFile(filename)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading file: %v\n", err)
			os.Exit(1)
		}
		source = string(content)
	} else {
		content, err := io.ReadAll(os.Stdin)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading stdin: %v\n", err)
			os.Exit(1)
		}
		source = string(content)
	}

	// Handle empty input
	if strings.TrimSpace(source) == "" {
		return
	}

	// Handle Markdown rendering
	if chromaMarkdown {
		md := goldmark.New(
			goldmark.WithExtensions(
				extension.GFM,
				highlighting.NewHighlighting(
					highlighting.WithStyle(chromaStyle),
					highlighting.WithFormatOptions(
						html.WithClasses(!chromaInline),
					),
				),
			),
			goldmark.WithParserOptions(
				parser.WithAutoHeadingID(),
			),
			goldmark.WithRendererOptions(
				ghtml.WithHardWraps(),
				ghtml.WithXHTML(),
			),
		)

		var buf bytes.Buffer
		if err := md.Convert([]byte(source), &buf); err != nil {
			fmt.Fprintf(os.Stderr, "Markdown rendering error: %v\n", err)
			os.Exit(1)
		}
		fmt.Print(buf.String())
		return
	}

	// Detect or use specified lexer
	var lexer chroma.Lexer
	if chromaLanguage != "" {
		lexer = lexers.Get(chromaLanguage)
		if lexer == nil {
			fmt.Fprintf(os.Stderr, "Unknown language: %s\n", chromaLanguage)
			os.Exit(1)
		}
	} else if filename != "" {
		lexer = lexers.Match(filename)
	}

	// Try content analysis if no lexer found
	if lexer == nil {
		lexer = lexers.Analyse(source)
	}

	// Fallback to plaintext
	if lexer == nil {
		lexer = lexers.Fallback
	}

	lexer = chroma.Coalesce(lexer)

	// Get style
	style := styles.Get(chromaStyle)
	if style == nil {
		style = styles.Fallback
	}

	// Create HTML formatter
	var formatter *html.Formatter
	if chromaInline {
		formatter = html.New(
			html.WithClasses(false),
			html.TabWidth(4),
		)
	} else {
		formatter = html.New(
			html.WithClasses(true),
			html.TabWidth(4),
		)
	}

	// Tokenize
	iterator, err := lexer.Tokenise(nil, source)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Tokenization error: %v\n", err)
		os.Exit(1)
	}

	// Format and output
	if err := formatter.Format(os.Stdout, style, iterator); err != nil {
		fmt.Fprintf(os.Stderr, "Formatting error: %v\n", err)
		os.Exit(1)
	}
}
