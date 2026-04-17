#!/usr/bin/env python3
"""Generate coverage badge SVG from test report"""

import json
import sys

def generate_badge(percentage):
    """Generate SVG badge for coverage percentage"""
    
    # Color based on percentage
    if percentage >= 90:
        color = "#4c1"  # Green
    elif percentage >= 70:
        color = "#fe7d37"  # Orange
    else:
        color = "#e05d44"  # Red
    
    label = "coverage"
    value = f"{percentage}%"
    
    # Calculate widths
    label_width = len(label) * 7 + 10
    value_width = len(value) * 7 + 10
    total_width = label_width + value_width
    
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{total_width}" height="20">
  <linearGradient id="b" x2="0" y2="100%">
    <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
    <stop offset="1" stop-opacity=".1"/>
  </linearGradient>
  <mask id="a">
    <rect width="{total_width}" height="20" rx="3" fill="#fff"/>
  </mask>
  <g mask="url(#a)">
    <path fill="#555" d="M0 0h{label_width}v20H0z"/>
    <path fill="{color}" d="M{label_width} 0h{value_width}v20H{label_width}z"/>
    <path fill="url(#b)" d="M0 0h{total_width}v20H0z"/>
  </g>
  <g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11">
    <text x="{label_width/2}" y="15" fill="#010101" fill-opacity=".3">{label}</text>
    <text x="{label_width/2}" y="14">{label}</text>
    <text x="{label_width + value_width/2}" y="15" fill="#010101" fill-opacity=".3">{value}</text>
    <text x="{label_width + value_width/2}" y="14">{value}</text>
  </g>
</svg>'''
    
    return svg

def main():
    try:
        with open('test-report.json', 'r') as f:
            report = json.load(f)
        
        percentage = report['coverage']['percentage']
        
        svg = generate_badge(percentage)
        
        with open('coverage-badge.svg', 'w') as f:
            f.write(svg)
        
        print(f"✅ Generated coverage badge: {percentage}%")
        
    except FileNotFoundError:
        print("❌ test-report.json not found. Run tests first.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
