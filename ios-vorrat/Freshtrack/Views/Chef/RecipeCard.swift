import SwiftUI

/// Recipe answer: ingredients (missing ones dimmed) and numbered steps.
struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if recipe.durationMinutes != nil || recipe.servings != nil {
                        HStack(spacing: 14) {
                            if let minutes = recipe.durationMinutes {
                                Label("\(minutes) Min.", systemImage: "clock")
                            }
                            if let servings = recipe.servings {
                                Label(servings == 1 ? "1 Portion" : "\(servings) Portionen", systemImage: "person.2")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Zutaten")
                    ForEach(recipe.ingredients) { ingredient in
                        HStack(spacing: 12) {
                            Image(systemName: ingredient.isAvailable ? "checkmark.circle.fill" : "cart")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(ingredient.isAvailable ? .white : Theme.secondary)
                                .frame(width: 22)
                            Text(ingredient.name)
                                .foregroundStyle(ingredient.isAvailable ? .white : Theme.secondary)
                            + Text(ingredient.isAvailable ? "" : " (fehlt dir noch)")
                                .foregroundStyle(Theme.secondary.opacity(0.8))
                            Spacer(minLength: 8)
                            Text(ingredient.amount)
                                .foregroundStyle(ingredient.isAvailable ? .white : Theme.secondary)
                                .monospacedDigit()
                        }
                        .font(.body)
                    }
                }

                Divider().overlay(Theme.hairline)

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Zubereitung")
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.surfaceHigh, in: .circle)
                            Text(step)
                                .font(.body)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(18)
        }
        .contentCard(radius: 26)
        .clipShape(.rect(cornerRadius: 26))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondary)
    }
}
